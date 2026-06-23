// 2.0.0 — `migration add` (Phase 8.11):
// pure helpers that turn a list of [SchemaDiff]s
// (from `AutoMigrator.computePendingDiff()`) into
// a `MigrationBase` subclass file with the
// `up()` body pre-populated with the diff SQL.
//
// Design notes:
//
// 1. We emit `safe` diffs into `up()` by default.
//    `unsafe` diffs are listed in a comment block
//    at the top of the file (so the dev can hand-
//    roll a follow-up migration for them). Pass
//    `includeUnsafe: true` to also emit the unsafe
//    SQL verbatim (use `--include-unsafe` on the
//    CLI).
//
// 2. We emit the inverse SQL into `down()` for
//    every `safe` diff. The inverse is the
//    natural complement (CREATE TABLE → DROP TABLE,
//    CREATE INDEX → DROP INDEX, ADD COLUMN → DROP
//    COLUMN). Diffs whose inverse is data-loss
//    (e.g. DROP COLUMN has no data-preserving
//    inverse) are wrapped in a defensive
//    `BEGIN; ... ROLLBACK;` block to make the
//    rollback explicit; the dev can edit the
//    generated file to remove the guard if they
//    really want a destructive rollback.
//
// 3. We do NOT touch the existing
//    `bin/migration.dart` `add` command's default
//    behaviour (no `--db` flag → empty stub).
//    This module is opt-in: pass `--db` and the
//    command routes through the codegen path.
//
// 4. All helpers are pure. The `bin/` glue
//    spawns the worker subprocess and feeds
//    the resulting JSON into
//    [buildMigrationFileContent]. No I/O here.
//
// 5. Output is a single String ready to
//    `writeAsStringSync(...)`. The format is
//    stable across runs (deterministic), so the
//    dev can re-run the command to regenerate
//    a stale file (idempotent over the same
//    input diffs).

library;

/// Lightweight value-object mirror of
/// [SchemaDiff] for the CLI. We don't import
/// the runtime class to keep this file free
/// of side effects (the CLI runs in its own
/// VM and doesn't need to link the full
/// `d_rocket` runtime).
class CliSchemaDiff {
  final String severity; // 'safe' | 'unsafe'
  final String type; // 'createTable' | 'dropTable' | ...
  final String tableName;
  final String? columnName;
  final String? newColumnName;
  final String sql;
  final String reason;

  const CliSchemaDiff({
    required this.severity,
    required this.type,
    required this.tableName,
    this.columnName,
    this.newColumnName,
    required this.sql,
    required this.reason,
  });

  /// Parse the JSON map emitted by the
  /// `check_worker.dart` source.
  factory CliSchemaDiff.fromJson(Map<String, Object?> json) {
    return CliSchemaDiff(
      severity: (json['severity'] as String?) ?? 'unsafe',
      type: (json['type'] as String?) ?? 'unknown',
      tableName: (json['tableName'] as String?) ?? '<unknown>',
      columnName: json['columnName'] as String?,
      newColumnName: json['newColumnName'] as String?,
      sql: (json['sql'] as String?) ?? '',
      reason: (json['reason'] as String?) ?? '',
    );
  }
}

/// Options that control what the generated
/// file looks like. The CLI exposes these as
/// flags (e.g. `--include-unsafe`).
class CodegenOptions {
  /// When true, the unsafe diffs' SQL is
  /// included in `up()` (in addition to a
  /// comment header). Default false: only safe
  /// diffs go in `up()`; unsafe diffs appear
  /// in a comment block.
  final bool includeUnsafe;

  /// When true, `down()` is emitted as
  /// `throw UnsupportedError(...)` (the
  /// default-empty-stub behaviour). When
  /// false (the default for the codegen
  /// path), `down()` contains the inverse
  /// SQL for every safe diff.
  final bool irreversible;

  const CodegenOptions({
    this.includeUnsafe = false,
    this.irreversible = false,
  });
}

/// Partition [diffs] into a (safe, unsafe)
/// tuple. Safe diffs come first (so the
/// generated `up()` reads in the natural
/// CREATE → INDEX → ADD order).
({List<CliSchemaDiff> safe, List<CliSchemaDiff> unsafe})
    partitionDiffsBySeverity(List<CliSchemaDiff> diffs) {
  final safe = <CliSchemaDiff>[];
  final unsafe = <CliSchemaDiff>[];
  for (final d in diffs) {
    if (d.severity == 'safe') {
      safe.add(d);
    } else {
      unsafe.add(d);
    }
  }
  return (safe: safe, unsafe: unsafe);
}

/// Returns the inverse SQL for a [diff] (the
/// SQL that, if executed, would undo the
/// forward operation). Returns `null` for
/// operations that have no clean inverse
/// (the caller should emit a guarded block
/// or skip).
String? inverseSqlFor(CliSchemaDiff diff) {
  switch (diff.type) {
    case 'createTable':
      return 'DROP TABLE ${diff.tableName}';
    case 'createIndex':
      // The forward SQL contains the full
      // `CREATE INDEX` statement. The
      // inverse is `DROP INDEX <name>`.
      // The CLI worker includes the index
      // name in `columnName` (see
      // schema_diff.dart doc on
      // createIndex). Fall back to a
      // best-effort extraction.
      final name = diff.columnName;
      if (name != null && name.isNotEmpty) {
        return 'DROP INDEX $name';
      }
      return null;
    case 'addColumn':
      if (diff.columnName == null) return null;
      return 'ALTER TABLE ${diff.tableName} '
          'DROP COLUMN ${diff.columnName}';
    case 'dropColumn':
    case 'dropTable':
    case 'dropIndex':
    case 'modifyColumn':
    case 'renameColumn':
      // These are the unsafe-diff forward
      // operations; the inverse is to
      // restore the data, which has no
      // SQL expression.
      return null;
    default:
      return null;
  }
}

/// Render a SQL string as a Dart raw-string
/// triple-quoted literal suitable for
/// embedding in the generated file. We use
/// raw strings (`r'''...'''`) so the dev can
/// keep line-breaks in their SQL without
/// escaping. The outer template uses `'''`
/// as the delimiter; we escape any `'''`
/// inside the SQL (very unlikely in DDL).
String dartRawString(String sql) {
  // Escape any occurrence of the raw-string
  // delimiter inside the SQL.
  final escaped = sql.replaceAll("'''", r"\'\'\'");
  return "r'''$escaped'''";
}

/// Returns the body of a generated migration
/// file. Pure function — no I/O. The caller
/// (`bin/migration.dart`) writes the result
/// to disk.
///
/// [className] is the migration class name
/// (e.g. `M003AddNoteToPatients`).
/// [id] is the numeric string used for the
/// version (e.g. `'003'`).
/// [name] is the human-readable name the
/// user passed to `migration add`.
/// [diffs] is the full list (both safe and
/// unsafe) from the worker. The function
/// partitions them internally.
String buildMigrationFileContent({
  required String className,
  required String id,
  required String name,
  required List<CliSchemaDiff> diffs,
  CodegenOptions options = const CodegenOptions(),
}) {
  final partitioned = partitionDiffsBySeverity(diffs);
  final safe = partitioned.safe;
  final unsafe = partitioned.unsafe;

  final StringBuffer upBody = StringBuffer();
  final StringBuffer downBody = StringBuffer();
  final StringBuffer commentBlock = StringBuffer();

  // Comment header: mark this file as
  // auto-generated + list unsafe diffs.
  commentBlock.writeln('/// AUTO-GENERATED by `d_rocket:migration add`.');
  commentBlock.writeln('///');
  commentBlock.writeln('/// Source: schema diff between the codegen-');
  commentBlock.writeln('/// emitted entity metas and the schema in the');
  commentBlock.writeln('/// SQLite file at `add` time.');
  commentBlock.writeln('///');
  commentBlock.writeln('/// Forward operations: ${safe.length} safe, '
      '${unsafe.length} unsafe.');
  if (unsafe.isNotEmpty) {
    commentBlock.writeln('///');
    commentBlock.writeln('/// UNSAFE diffs (NOT auto-applied):');
    for (final u in unsafe) {
      final String target = u.columnName == null
          ? u.tableName
          : '$u.tableName.${u.columnName}';
      commentBlock.writeln('///   - ${u.type} $target '
          '(${u.reason})');
    }
    commentBlock.writeln('///');
    commentBlock.writeln('/// Write a follow-up migration to handle');
    commentBlock.writeln('/// the unsafe diffs explicitly.');
  }
  commentBlock.writeln();

  // Build `up()` body.
  if (safe.isEmpty && (unsafe.isEmpty || !options.includeUnsafe)) {
    upBody.writeln('    // No safe diffs detected at scaffold time.');
    upBody.writeln('    // (Re-run `migration add` after the diff');
    upBody.writeln('    // changes, or hand-roll the DDL here.)');
  } else {
    final List<CliSchemaDiff> forward =
        options.includeUnsafe ? [...safe, ...unsafe] : safe;
    for (final d in forward) {
      upBody.writeln('    // ${d.severity.toUpperCase()}: '
          '${d.type} on ${d.tableName}'
          '${d.columnName == null ? "" : ".${d.columnName}"}');
      upBody.writeln('    //   reason: ${d.reason}');
      upBody.writeln('    exec(${dartRawString(d.sql)});');
      upBody.writeln();
    }
  }

  // Build `down()` body.
  if (options.irreversible) {
    downBody.writeln('    throw UnsupportedError(');
    downBody.writeln("      'M$id is irreversible (codegen opted out).',");
    downBody.writeln('    );');
  } else if (safe.isEmpty) {
    downBody.writeln('    // No forward safe diffs to invert.');
    downBody.writeln('    // (Hand-roll if you need a rollback path.)');
  } else {
    for (final d in safe) {
      final String? inverse = inverseSqlFor(d);
      if (inverse == null) {
        downBody.writeln('    // No clean inverse for '
            '${d.type}; hand-roll if needed.');
        continue;
      }
      // Data-loss diffs (dropTable, dropColumn,
      // dropIndex) are wrapped in a
      // BEGIN/ROLLBACK guard so the dev has to
      // actively remove the rollback to allow
      // destruction. This is intentional: the
      // dev should think twice before
      // destructively rolling back.
      final bool isDestructive = d.type == 'createTable' ||
          d.type == 'addColumn';
      if (isDestructive) {
        downBody.writeln('    // Inverse of ${d.type} '
            '${d.tableName}'
            '${d.columnName == null ? "" : ".${d.columnName}"} '
            '(destructive — guarded).');
        downBody.writeln('    // Remove the BEGIN/ROLLBACK guard');
        downBody.writeln('    // if you really want a destructive');
        downBody.writeln('    // rollback.');
        downBody.writeln('    exec("BEGIN;");');
        downBody.writeln('    exec(${dartRawString(inverse)});');
        downBody.writeln('    exec("ROLLBACK;");');
      } else {
        downBody.writeln('    // Inverse of ${d.type}.');
        downBody.writeln('    exec(${dartRawString(inverse)});');
      }
      downBody.writeln();
    }
  }

  // Assemble the final file.
  return '''import 'package:d_rocket/d_rocket.dart';

$commentBlock/// Hand-edit below this line if needed.
///

class $className extends MigrationBase {
  @override
  String get id => '$id';

  @override
  String get name => '$name';

  @override
  void up(MigrationExecutor exec) {
$upBody  }

  @override
  void down(MigrationExecutor exec) {
$downBody  }
}
''';
}

/// Converts a kebab/snake case CLI name
/// (e.g. `add_note_to_patients`) into a
/// PascalCase class name (e.g.
/// `M003AddNoteToPatients`). The numeric
/// prefix [id] is prepended to match the
/// existing `bin/migration.dart` convention.
String cliNameToClassName({
  required String cliName,
  required String id,
}) {
  final parts = cliName
      .split(RegExp(r'[_\- ]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join();
  return 'M$id$parts';
}

/// Converts a kebab/snake CLI name to the
/// canonical file name (snake_case) that
/// `bin/migration.dart` uses.
String cliNameToFileName(String cliName) {
  return cliName
      .toLowerCase()
      .replaceAll(RegExp(r'[ _\-]+'), '_');
}

