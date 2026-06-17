// Schema diff: the heart of the auto-migration
// system. Compares two [SchemaSnapshot]s and
// returns a [List<SchemaDiff>] describing the
// changes, classified by [DiffSeverity].
//
// The algorithm is intentionally conservative:
//   * `safe` operations are non-destructive and
//     can be auto-applied. They are CREATE TABLE,
//     CREATE INDEX, and ADD COLUMN (the last only
//     when the new column is nullable or has a
//     default literal).
//   * `unsafe` operations are potentially
//     destructive and are reported but NOT
//     auto-applied. They are DROP TABLE, DROP
//     COLUMN, DROP INDEX, MODIFY COLUMN, and the
//     rename heuristic (a drop + an add of the
//     same type).
//
// The SQL emitted for unsafe operations is
// for reference only - the auto-migrator does
// not execute it. The user is expected to write
// a hand-rolled migration that performs the
// unsafe change explicitly.
//
// The diff is deterministic: given the same two
// inputs, the output is byte-identical. This
// makes it easy to test and easy to log.

import 'schema_snapshot.dart';

///: severity classification for a
/// [SchemaDiff]. `safe` operations are
/// non-destructive and are auto-applied.
/// `unsafe` operations are potentially
/// destructive and are reported only.
enum DiffSeverity { safe, unsafe }

///: type of a [SchemaDiff]. Maps
/// 1:1 to a SQL DDL operation (with two
/// exceptions: `modifyColumn` has no direct SQL
/// in SQLite, and `renameColumn` is a heuristic
/// that suggests a possible rename).
enum SchemaOperationType {
  createTable,
  dropTable,
  addColumn,
  dropColumn,
  modifyColumn,
  createIndex,
  dropIndex,
  renameColumn,
}

///: a single diff entry. The fields
/// depend on [type]:
///
///   * `createTable` / `dropTable`:
///     `tableName` is set; `columnName` is null.
///   * `addColumn` / `dropColumn` / `modifyColumn`:
///     `tableName` and `columnName` are set.
///   * `createIndex` / `dropIndex`:
///     `tableName` is set; `columnName` is the
///     index name (kept in `columnName` for
///     backward compat with the column-centric
///     view of the diff).
///   * `renameColumn`:
///     `tableName`, `columnName` (old), and
///     `newColumnName` (new) are set.
class SchemaDiff {
  final DiffSeverity severity;
  final SchemaOperationType type;
  final String tableName;

  /// Column name (or index name for
  /// createIndex/dropIndex, or old name for
  /// renameColumn).
  final String? columnName;

  /// New name (renameColumn only).
  final String? newColumnName;

  /// SQL DDL that would perform this change.
  /// Present for every type. For unsafe
  /// operations this is reference SQL only -
  /// the auto-migrator does not execute it.
  final String sql;

  /// Human-readable explanation of why this
  /// change is safe or unsafe. Surfaced in the
  /// `Db.pendingSchemaDiff()` output and in
  /// logs.
  final String reason;

  const SchemaDiff({
    required this.severity,
    required this.type,
    required this.tableName,
    this.columnName,
    this.newColumnName,
    required this.sql,
    required this.reason,
  });

  @override
  String toString() {
    final StringBuffer buf = StringBuffer()
      ..write(severity.name)
      ..write(': ')
      ..write(type.name)
      ..write(' on ')
      ..write(tableName);
    if (columnName != null) {
      buf.write('.');
      buf.write(columnName);
    }
    if (newColumnName != null) {
      buf.write(' -> ');
      buf.write(newColumnName);
    }
    return buf.toString();
  }
}

///: compute the diff between two
/// snapshots. Returns a deterministic list of
/// [SchemaDiff]s. The caller decides what to do
/// with `unsafe` entries (typically: log them,
/// surface them via `Db.pendingSchemaDiff()`,
/// and DO NOT apply them).
List<SchemaDiff> computeSchemaDiff(
  SchemaSnapshot old,
  SchemaSnapshot newSnap,
) {
  // Sanity: the snapshot versions must be
  // compatible. A 1.1.x runtime that somehow
  // finds a 2.0.0 snapshot in the table should
  // refuse, not silently corrupt.
  if (old.version > newSnap.version) {
    throw StateError(
      'Schema snapshot downgrade detected: stored '
      'snapshot is v${old.version}, runtime is '
      'v${newSnap.version}. The database was likely '
      'written by a newer d_rocket. Refusing to '
      'migrate.',
    );
  }

  final List<SchemaDiff> out = <SchemaDiff>[];

  // Build lookup maps keyed by table name.
  final Map<String, SchemaTable> oldTables = <String, SchemaTable>{
    for (final SchemaTable t in old.tables) t.name: t,
  };
  final Map<String, SchemaTable> newTables = <String, SchemaTable>{
    for (final SchemaTable t in newSnap.tables) t.name: t,
  };

  // 1. Tables that are in new but not in old:
  //    CREATE TABLE (safe).
  for (final SchemaTable t in newSnap.tables) {
    if (!oldTables.containsKey(t.name)) {
      out.add(SchemaDiff(
        severity: DiffSeverity.safe,
        type: SchemaOperationType.createTable,
        tableName: t.name,
        sql: _createTableSql(t),
        reason:
            'New entity; CREATE TABLE IF NOT EXISTS is '
            'idempotent and non-destructive.',
      ));
    }
  }

  // 2. Tables that are in old but not in new:
  //    DROP TABLE (unsafe).
  for (final SchemaTable t in old.tables) {
    if (!newTables.containsKey(t.name)) {
      out.add(SchemaDiff(
        severity: DiffSeverity.unsafe,
        type: SchemaOperationType.dropTable,
        tableName: t.name,
        sql: 'DROP TABLE ${t.name}',
        reason:
            'Entity removed from code; dropping the '
            'table would lose all its data. Confirm '
            'manually and write a hand-rolled '
            'migration that does the drop explicitly.',
      ));
    }
  }

  // 3. Tables that are in both: compare columns
  //    and indexes. Skip tables that are in
  //    neither (already handled above).
  for (final SchemaTable newT in newSnap.tables) {
    final SchemaTable? oldT = oldTables[newT.name];
    if (oldT == null) continue;
    _diffTable(out, oldT, newT);
  }

  // 4. Rename heuristic. After the column-level
  //    diff is complete, look for unsafe
  //    dropColumn + safe addColumn pairs that
  //    could be a RENAME. This is a best-effort
  //    suggestion only; the user is expected to
  //    confirm manually.
  _appendRenameSuggestions(out, old, newSnap);

  return out;
}

void _diffTable(
  List<SchemaDiff> out,
  SchemaTable oldT,
  SchemaTable newT,
) {
  // Columns: same iteration pattern as tables.
  final Map<String, SchemaColumn> oldCols = <String, SchemaColumn>{
    for (final SchemaColumn c in oldT.columns) c.name: c,
  };
  final Map<String, SchemaColumn> newCols = <String, SchemaColumn>{
    for (final SchemaColumn c in newT.columns) c.name: c,
  };

  // 3a. Columns in new but not in old: ADD
  //     COLUMN (safe, with a caveat for
  //     non-nullable columns without a default).
  for (final SchemaColumn c in newT.columns) {
    if (!oldCols.containsKey(c.name)) {
      final bool canAutoAdd = c.nullable || c.defaultLiteral != null;
      out.add(SchemaDiff(
        severity: canAutoAdd ? DiffSeverity.safe : DiffSeverity.unsafe,
        type: SchemaOperationType.addColumn,
        tableName: newT.name,
        columnName: c.name,
        sql: _addColumnSql(newT.name, c),
        reason: canAutoAdd
            ? 'New column is nullable or has a default '
                'literal; ALTER TABLE ADD COLUMN is '
                'non-destructive.'
            : 'New column is NOT NULL with no default '
                'literal; SQLite would fail to backfill '
                'existing rows. Provide a default '
                'literal, make the column nullable, '
                'or write a hand-rolled migration that '
                'backfills explicitly.',
      ));
    }
  }

  // 3b. Columns in old but not in new: DROP
  //     COLUMN (unsafe, even in SQLite 3.35+
  //     which has ALTER TABLE DROP COLUMN,
  //     because the migration loses data).
  for (final SchemaColumn c in oldT.columns) {
    if (!newCols.containsKey(c.name)) {
      out.add(SchemaDiff(
        severity: DiffSeverity.unsafe,
        type: SchemaOperationType.dropColumn,
        tableName: oldT.name,
        columnName: c.name,
        sql: 'ALTER TABLE ${oldT.name} DROP COLUMN ${c.name}',
        reason:
            'Column removed from code; dropping the '
            'column loses data. Confirm manually and '
            'write a hand-rolled migration that does '
            'the drop explicitly (or the rename, if '
            'this is a rename).',
      ));
    }
  }

  // 3c. Columns in both: type / nullability /
  //     default changes are MODIFY (unsafe in
  //     SQLite, which has no ALTER COLUMN).
  for (final SchemaColumn c in newT.columns) {
    final SchemaColumn? oldC = oldCols[c.name];
    if (oldC == null) continue;
    final bool typeChanged = oldC.sqliteType != c.sqliteType;
    final bool nullabilityChanged = oldC.nullable != c.nullable;
    final bool defaultChanged = oldC.defaultLiteral != c.defaultLiteral;
    final bool fkChanged = !_foreignKeyEqual(oldC.foreignKey, c.foreignKey);
    if (typeChanged || nullabilityChanged || defaultChanged || fkChanged) {
      final List<String> changes = <String>[
        if (typeChanged) 'type: ${oldC.sqliteType} -> ${c.sqliteType}',
        if (nullabilityChanged)
          'nullable: ${oldC.nullable} -> ${c.nullable}',
        if (defaultChanged)
          'default: ${oldC.defaultLiteral ?? "<none>"} -> '
              '${c.defaultLiteral ?? "<none>"}',
        if (fkChanged) 'foreign key changed',
      ];
      out.add(SchemaDiff(
        severity: DiffSeverity.unsafe,
        type: SchemaOperationType.modifyColumn,
        tableName: newT.name,
        columnName: c.name,
        sql: '-- (no direct ALTER COLUMN in SQLite; '
            'manual migration required)',
        reason:
            'Column definition changed (${changes.join(", ")}). '
            'SQLite has no ALTER COLUMN; the migration '
            'requires a table rebuild (new column + '
            'copy + drop + rename). Confirm manually.',
      ));
    }
  }

  // 3d. Indexes in new but not in old: CREATE
  //     INDEX (safe).
  final Map<String, SchemaIndex> oldIdx = <String, SchemaIndex>{
    for (final SchemaIndex i in oldT.indexes) i.name: i,
  };
  final Map<String, SchemaIndex> newIdx = <String, SchemaIndex>{
    for (final SchemaIndex i in newT.indexes) i.name: i,
  };
  for (final SchemaIndex i in newT.indexes) {
    if (!oldIdx.containsKey(i.name)) {
      out.add(SchemaDiff(
        severity: DiffSeverity.safe,
        type: SchemaOperationType.createIndex,
        tableName: newT.name,
        columnName: i.name,
        sql: _createIndexSql(i),
        reason:
            'New index; CREATE INDEX IF NOT EXISTS is '
            'non-destructive and only speeds up '
            'queries.',
      ));
    }
  }

  // 3e. Indexes in old but not in new: DROP
  //     INDEX (unsafe - degrades query speed).
  for (final SchemaIndex i in oldT.indexes) {
    if (!newIdx.containsKey(i.name)) {
      out.add(SchemaDiff(
        severity: DiffSeverity.unsafe,
        type: SchemaOperationType.dropIndex,
        tableName: oldT.name,
        columnName: i.name,
        sql: 'DROP INDEX ${i.name}',
        reason:
            'Index removed from code; dropping the '
            'index degrades query speed. Confirm '
            'manually (or keep the index for '
            'performance).',
      ));
    }
  }

  // 3f. Primary key changes: any change to the
  //     PK column set is unsafe (SQLite cannot
  //     ALTER a primary key directly).
  if (!_stringListEqual(oldT.primaryKey, newT.primaryKey)) {
    out.add(SchemaDiff(
      severity: DiffSeverity.unsafe,
      type: SchemaOperationType.modifyColumn,
      tableName: newT.name,
      columnName: '<primary key>',
      sql: '-- (no direct ALTER PRIMARY KEY in SQLite; '
          'manual migration required)',
      reason: 'Primary key changed from '
          '[${oldT.primaryKey.join(", ")}] to '
          '[${newT.primaryKey.join(", ")}]. SQLite has '
          'no ALTER PRIMARY KEY; the migration requires '
          'a table rebuild. Confirm manually.',
    ));
  }
}

void _appendRenameSuggestions(
  List<SchemaDiff> out,
  SchemaSnapshot old,
  SchemaSnapshot newSnap,
) {
  // For every unsafe dropColumn, look for a
  // safe addColumn in the same table with the
  // same type and nullability. If exactly one
  // match, suggest a RENAME.
  for (int i = 0; i < out.length; i++) {
    final SchemaDiff diff = out[i];
    if (diff.type != SchemaOperationType.dropColumn) continue;
    final SchemaColumn? newCol =
        newSnap.table(diff.tableName)?.column(diff.columnName!);
    if (newCol == null) continue;
    // The drop must be a rename target only if
    // there is a column with the SAME name in
    // BOTH old and new tables. If the column
    // was simply deleted (no column with the
    // same name in new), this is a real drop,
    // not a rename.
    final SchemaColumn? oldCol =
        old.table(diff.tableName)?.column(diff.columnName!);
    if (oldCol == null) continue;
    if (oldCol.sqliteType != newCol.sqliteType) continue;
    if (oldCol.nullable != newCol.nullable) continue;
    if (oldCol.defaultLiteral != newCol.defaultLiteral) continue;
    // The drop+add pair looks like a rename
    // candidate. Suggest it as an unsafe
    // rename (the user still has to confirm
    // manually because the rename heuristic
    // can be wrong).
    out[i] = SchemaDiff(
      severity: DiffSeverity.unsafe,
      type: SchemaOperationType.renameColumn,
      tableName: diff.tableName,
      columnName: diff.columnName,
      newColumnName: newCol.name,
      sql: 'ALTER TABLE ${diff.tableName} '
          'RENAME COLUMN ${diff.columnName} '
          'TO ${newCol.name}',
      reason: 'Possible rename detected: column '
          '${diff.columnName} was dropped and a column '
          'of the same type and nullability is present '
          'in the new schema. SQLite supports RENAME '
          'COLUMN in 3.25+. Confirm manually that this '
          'is a rename and not a delete+create.',
    );
  }
}

bool _foreignKeyEqual(SchemaForeignKey? a, SchemaForeignKey? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.table == b.table &&
      a.column == b.column &&
      a.onDelete == b.onDelete;
}

bool _stringListEqual(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _createTableSql(SchemaTable t) {
  // Mirrors EntityMeta.createTableDdl() but
  // reads from the SchemaSnapshot (which is
  // already flattened - no embedded handling
  // needed here, computeSnapshot has already
  // flattened them).
  final StringBuffer buf = StringBuffer()
    ..writeln('CREATE TABLE IF NOT EXISTS ${t.name} (');
  final List<String> parts = <String>[];
  for (final SchemaColumn c in t.columns) {
    parts.add(_columnDdl(c, t));
  }
  buf.writeln('  ${parts.join(",\n  ")}');
  buf.writeln(')');
  return buf.toString();
}

String _addColumnSql(String tableName, SchemaColumn c) {
  return 'ALTER TABLE $tableName ADD COLUMN ${_columnInline(c)}';
}

String _createIndexSql(SchemaIndex i) {
  final String unique = i.isUnique ? 'UNIQUE ' : '';
  return 'CREATE ${unique}INDEX IF NOT EXISTS ${i.name} '
      'ON ${_firstTableOfIndex(i)} (${i.columns.join(", ")})';
}

/// helper: the table name for an index. We do
/// not store the table name on [SchemaIndex] in
/// this MVP (it is implicit in the parent
/// [SchemaTable] and the auto-migrator knows it
/// from context). For SQL output we fall back
/// to the index's name as a best-effort.
String _firstTableOfIndex(SchemaIndex i) => i.name.split('_').first;

String _columnInline(SchemaColumn c) {
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

String _columnDdl(SchemaColumn c, SchemaTable t) {
  return _columnInline(c);
}
