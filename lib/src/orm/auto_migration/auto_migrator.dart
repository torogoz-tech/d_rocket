// AutoMigrator: the orchestrator that runs the
// auto-migration end-to-end.
//
// Flow:
//   1. Ensure the d_rocket_schema_state table
//      exists (delegated to SchemaState).
//   2. Read the last applied SchemaSnapshot from
//      the table (or null on fresh install).
//   3. Compute the new SchemaSnapshot from the
//      list of EntityMeta passed in.
//   4. Compute the diff between old and new.
//   5. Filter the diff into "safe" (auto-
//      applicable) and "unsafe" (reported only)
//      operations.
//   6. Apply every safe operation in a single
//      transaction, then write the new snapshot
//      in the same transaction. On exception,
//      the transaction rolls back and the
//      schema state is unchanged.
//   7. Return the list of unsafe operations so
//      the caller can log them or surface them
//      via Db.pendingSchemaDiff().
//
// The auto-migrator NEVER applies unsafe
// operations. The user is expected to write a
// hand-rolled migration that performs the unsafe
// change explicitly. This is the conservative
// default: the auto-migrator never destroys
// data silently.

import 'dart:async';

import '../async_query_provider.dart';
import '../entity_meta.dart';
import 'schema_diff.dart';
import 'schema_snapshot.dart';
import 'schema_state.dart';

///: the result of an auto-migration
/// run. Bundles the safe diffs that were
/// applied (for logging) and the unsafe diffs
/// that were NOT applied (for the caller to
/// surface).
class AutoMigrationResult {
  /// The safe diffs that were applied. Empty on
  /// a fresh install where the entire schema was
  /// the "safe" diff. Empty on a re-run where
  /// nothing changed.
  final List<SchemaDiff> applied;

  /// The unsafe diffs that were reported but
  /// NOT applied. The user is expected to
  /// handle these manually (typically by
  /// writing a hand-rolled migration that
  /// performs the unsafe change explicitly).
  /// Empty if there are no unsafe changes.
  final List<SchemaDiff> unsafe;

  /// The new SchemaSnapshot that was written
  /// to the d_rocket_schema_state table. Exposed
  /// for logging and for `Db.pendingSchemaDiff()`
  /// (which returns the diff between THIS
  /// snapshot and the NEXT one to be applied).
  final SchemaSnapshot snapshot;

  const AutoMigrationResult({
    required this.applied,
    required this.unsafe,
    required this.snapshot,
  });

  @override
  String toString() =>
      'AutoMigrationResult(applied: ${applied.length}, '
      'unsafe: ${unsafe.length})';
}

///: the auto-migrator.
///
/// Created by [_SqliteRocketContext] when
/// `autoMigrate: true` is passed to `Db.open`.
/// Application code does not construct an
/// `AutoMigrator` directly; it interacts with
/// it indirectly via `Db.pendingSchemaDiff()`.
class AutoMigrator {
  /// Creates an auto-migrator backed by
  /// [provider] for the schema described by
  /// [entityMetas]. The provider is expected
  /// to be the same connection that handles
  /// user data writes (so the snapshot read
  /// and write participate in the caller's
  /// transaction).
  AutoMigrator({
    required AsyncQueryProvider provider,
    required List<EntityMeta> entityMetas,
  })  : _provider = provider,
        _state = SchemaState(provider: provider),
        _entityMetas = entityMetas;

  final AsyncQueryProvider _provider;
  final SchemaState _state;
  final List<EntityMeta> _entityMetas;

  ///: applies the auto-migration. Returns
  /// the result (with the safe diffs that were
  /// applied and the unsafe diffs that were
  /// reported).
  ///
  /// Throws if the schema is malformed (e.g.
  /// a snapshot from a newer d_rocket is found
  /// in the table) or if a safe DDL fails
  /// (e.g. a CREATE TABLE fails because the
  /// table already exists with a different
  /// shape). On any exception, the transaction
  /// rolls back and the database is unchanged.
  Future<AutoMigrationResult> run() async {
    // 1. Compute the new snapshot from the
    //    codegen-emitted entity list. The
    //    snapshot is deterministic; the same
    //    entity list always produces the same
    //    JSON.
    final SchemaSnapshot newSnapshot =
        computeSnapshot(_entityMetas);

    // 2. Read the old snapshot. null on fresh
    //    install.
    final SchemaSnapshot? oldSnapshot = await _state.read();

    // 3. Compute the diff. This also performs
    //    the version-sanity check (refuses to
    //    run if old > new).
    final List<SchemaDiff> allDiffs;
    if (oldSnapshot == null) {
      // Fresh install: every CREATE TABLE and
      // CREATE INDEX in the new snapshot is a
      // safe diff. We do not report "drop"
      // diffs because there is no old schema
      // to drop from.
      allDiffs = _freshInstallDiffs(newSnapshot);
    } else {
      allDiffs = computeSchemaDiff(oldSnapshot, newSnapshot);
    }

    // 4. Split into safe and unsafe.
    final List<SchemaDiff> safe = <SchemaDiff>[
      for (final SchemaDiff d in allDiffs)
        if (d.severity == DiffSeverity.safe) d,
    ];
    final List<SchemaDiff> unsafe = <SchemaDiff>[
      for (final SchemaDiff d in allDiffs)
        if (d.severity == DiffSeverity.unsafe) d,
    ];

    // 5. Apply the safe diffs in a single
    //    transaction, then write the new
    //    snapshot in the same transaction. On
    //    any DDL failure, the transaction
    //    rolls back and the database is
    //    unchanged.
    //
    //    Special case: when there are unsafe
    //    diffs, we DO NOT write the new
    //    snapshot. The unsafe diffs keep
    //    showing up in `pendingSchemaDiff()`
    //    on every reopen until the user
    //    handles them (typically by writing a
    //    hand-rolled migration that performs
    //    the unsafe change explicitly, then
    //    re-opening). The safe diffs were
    //    applied, so the next open will not
    //    re-apply them - the auto-migrator
    //    reads the actual database schema
    //    (via the snapshot, which is the v1
    //    schema) and the entity list (v2) and
    //    sees only the unsafe diffs as
    //    pending.
    //
    //    Trade-off: if the user adds a SAFE
    //    change while there is an outstanding
    //    UNSAFE diff, the safe change will
    //    not show up in pendingSchemaDiff
    //    until the unsafe is handled (the
    //    snapshot is the v1 schema, so the
    //    diff is v2 - v1 = unsafe only). This
    //    is intentional: a pending unsafe
    //    diff is a louder signal than a
    //    pending safe change, and we want the
    //    user to handle the unsafe first.
    final bool hasUnsafe = unsafe.isNotEmpty;
    if (safe.isNotEmpty) {
      await _provider.beginTransactionAsync();
      try {
        for (final SchemaDiff d in safe) {
          // Each [SchemaDiff.sql] is exactly one
          // SQL statement (multi-line, but a
          // single statement). The sqlite3
          // package's `execute` accepts multi-
          // line SQL - newline characters inside
          // a CREATE TABLE body are insignificant
          // whitespace. So we pass the whole
          // string as one call. We do NOT split
          // on newlines (splitting is wrong: a
          // multi-line CREATE TABLE is one
          // statement, not many).
          await _provider.executeAsync(d.sql);
        }
        if (!hasUnsafe) {
          // Write the new snapshot INSIDE the
          // transaction. If any DDL failed,
          // the write is rolled back too, so
          // the snapshot never gets ahead of
          // the actual schema.
          await _state.write(newSnapshot);
        }
        await _provider.commitAsync();
      } catch (_) {
        await _provider.rollbackAsync();
        rethrow;
      }
    } else if (oldSnapshot == null && !hasUnsafe) {
      // Fresh install with no entities. Still
      // record the (empty) snapshot so the
      // next run knows we are not on a fresh
      // install anymore. (Unsafe is impossible
      // on a fresh install - there is no old
      // schema to drop.)
      await _state.write(newSnapshot);
    } else if (!hasUnsafe) {
      // Nothing changed. Still record the new
      // snapshot so the schema state matches
      // the codegen-emitted entity list exactly
      // (e.g. after a re-run with a small
      // non-semantic change). Cheap - one
      // INSERT OR REPLACE.
      await _state.write(newSnapshot);
    }

    return AutoMigrationResult(
      applied: safe,
      unsafe: unsafe,
      snapshot: newSnapshot,
    );
  }

  ///: returns the diff between the
  /// current schema and the last applied
  /// snapshot, WITHOUT applying anything. Used
  /// by `Db.pendingSchemaDiff()` to let the
  /// caller inspect what would change before
  /// opening with `autoMigrate: true`.
  Future<List<SchemaDiff>> computePendingDiff() async {
    final SchemaSnapshot newSnapshot =
        computeSnapshot(_entityMetas);
    final SchemaSnapshot? oldSnapshot = await _state.read();
    if (oldSnapshot == null) {
      return _freshInstallDiffs(newSnapshot);
    }
    return computeSchemaDiff(oldSnapshot, newSnapshot);
  }

  /// helper: on a fresh install, the diff is
  /// "every CREATE TABLE / CREATE INDEX in the
  /// new snapshot". We do not generate "drop"
  /// diffs because there is no old schema to
  /// drop from.
  List<SchemaDiff> _freshInstallDiffs(SchemaSnapshot newSnapshot) {
    final List<SchemaDiff> out = <SchemaDiff>[];
    for (final SchemaTable t in newSnapshot.tables) {
      out.add(SchemaDiff(
        severity: DiffSeverity.safe,
        type: SchemaOperationType.createTable,
        tableName: t.name,
        sql: _createTableSqlForFreshInstall(t),
        reason:
            'Fresh install: entity ${t.name} does '
            'not exist yet. CREATE TABLE IF NOT '
            'EXISTS is idempotent.',
      ));
      for (final SchemaIndex i in t.indexes) {
        out.add(SchemaDiff(
          severity: DiffSeverity.safe,
          type: SchemaOperationType.createIndex,
          tableName: t.name,
          columnName: i.name,
          sql: 'CREATE ${i.isUnique ? "UNIQUE " : ""}INDEX '
              'IF NOT EXISTS ${i.name} '
              'ON ${t.name} (${i.columns.join(", ")})',
          reason:
              'Fresh install: index ${i.name} does '
              'not exist yet.',
        ));
      }
    }
    return out;
  }

  String _createTableSqlForFreshInstall(SchemaTable t) {
    // Mirrors the createTableDdl output from
    // computeSchemaDiff. Kept duplicated here
    // rather than re-using the private
    // helper there, to keep the two paths
    // (fresh install vs incremental diff)
    // independent.
    final StringBuffer buf = StringBuffer()
      ..writeln('CREATE TABLE IF NOT EXISTS ${t.name} (');
    final List<String> parts = <String>[];
    for (final SchemaColumn c in t.columns) {
      parts.add(_columnDdl(c));
    }
    buf.writeln('  ${parts.join(",\n  ")}');
    buf.writeln(')');
    return buf.toString();
  }

  String _columnDdl(SchemaColumn c) {
    final StringBuffer buf = StringBuffer()..write('${c.name} ');
    if (c.isPrimaryKey) {
      if (c.isAutoIncrement && c.sqliteType == 'INTEGER') {
        buf.write('INTEGER PRIMARY KEY AUTOINCREMENT');
      } else {
        buf.write('${c.sqliteType} PRIMARY KEY');
      }
    } else {
      buf.write(c.sqliteType);
      if (!c.nullable) {
        buf.write(' NOT NULL');
      }
      if (c.defaultLiteral != null) {
        buf.write(' DEFAULT ${c.defaultLiteral}');
      }
      if (c.foreignKey != null) {
        buf.write(
            ' REFERENCES ${c.foreignKey!.table}(${c.foreignKey!.column})');
      }
    }
    return buf.toString();
  }
}
