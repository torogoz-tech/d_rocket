// 2.0.0 — `migration add` (Phase 8.11):
// pure helpers that turn a list of [SchemaDiff]s
// (from `AutoMigrator.computePendingDiff()`) into
// a `MigrationBase` subclass file with the
// `up()` body pre-populated with the diff SQL.
//
// Design notes:
//
// 1. We emit every diff with executable SQL into
//    `up()`, including unsafe ALTER/DROP operations.
//    Unsafe operations are surrounded by explicit
//    review warnings. Diffs without executable SQL
//    remain as manual TODO blocks.
//
// 2. We emit the inverse SQL into `down()` for
//    every diff where a clean inverse is known. The inverse is the
//    natural complement (CREATE TABLE → DROP TABLE,
//    CREATE INDEX → DROP INDEX, ADD COLUMN → DROP
//    COLUMN). Operations without enough metadata
//    for a clean inverse are called out for manual
//    rollback work.
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
  /// Retained for CLI/API compatibility. Executable
  /// unsafe SQL is now emitted by default so the
  /// generated migration covers the complete diff.
  /// The generated source still marks it for review.
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
    case 'renameColumn':
      if (diff.columnName == null || diff.newColumnName == null) {
        return null;
      }
      return 'ALTER TABLE ${diff.tableName} RENAME COLUMN '
          '${diff.newColumnName} TO ${diff.columnName}';
    case 'dropColumn':
    case 'dropTable':
    case 'dropIndex':
    case 'modifyColumn':
      // These are the unsafe-diff forward
      // operations; the inverse is to
      // restore the data, which has no
      // SQL expression.
      return null;
    default:
      return null;
  }
}

/// Whether [diff] contains SQL that can be passed to
/// `MigrationExecutor.exec`. Some SQLite schema changes
/// intentionally carry a comment explaining that a table
/// rebuild is required instead of executable SQL.
bool hasExecutableSql(CliSchemaDiff diff) {
  final sql = diff.sql.trimLeft();
  return sql.isNotEmpty && !sql.startsWith('--');
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
  final executableUnsafe = unsafe.where(hasExecutableSql).toList();
  final manualUnsafe = unsafe.where((d) => !hasExecutableSql(d)).toList();
  final forward = <CliSchemaDiff>[...safe, ...executableUnsafe];

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
      '${executableUnsafe.length} unsafe executable, '
      '${manualUnsafe.length} manual.');
  if (unsafe.isNotEmpty) {
    commentBlock.writeln('///');
    commentBlock.writeln('/// UNSAFE diffs (REVIEW REQUIRED):');
    for (final u in unsafe) {
      final String target =
          u.columnName == null ? u.tableName : '$u.tableName.${u.columnName}';
      commentBlock.writeln('///   - ${u.type} $target '
          '(${u.reason})');
    }
    commentBlock.writeln('///');
    commentBlock.writeln('/// Executable unsafe SQL is included below,');
    commentBlock.writeln('/// but must be reviewed before applying it.');
  }
  commentBlock.writeln();

  // Build `up()` body.
  if (forward.isEmpty && manualUnsafe.isEmpty) {
    upBody.writeln('    // No executable diffs detected at scaffold time.');
    upBody.writeln('    // (Re-run `migration add` after the diff');
    upBody.writeln('    // changes, or hand-roll the DDL here.)');
  } else {
    for (final d in forward) {
      if (d.severity == 'unsafe') {
        upBody.writeln('    // WARNING: review this unsafe operation');
        upBody.writeln('    // carefully before applying it to data.');
      }
      upBody.writeln('    // ${d.severity.toUpperCase()}: '
          '${d.type} on ${d.tableName}'
          '${d.columnName == null ? "" : ".${d.columnName}"}');
      upBody.writeln('    //   reason: ${d.reason}');
      upBody.writeln('    exec(${dartRawString(d.sql)});');
      upBody.writeln();
    }
    for (final d in manualUnsafe) {
      upBody.writeln('    // MANUAL REQUIRED: ${d.type} on '
          '${d.tableName}${d.columnName == null ? "" : ".${d.columnName}"}');
      upBody.writeln('    // reason: ${d.reason}');
      upBody.writeln('    // SQLite requires a table rebuild or custom');
      upBody.writeln('    // DDL for this change. Add the SQL here.');
      upBody.writeln('    // source: ${d.sql.replaceAll("\n", " | ")}');
      upBody.writeln();
    }
  }

  // Build `down()` body.
  if (options.irreversible) {
    downBody.writeln('    throw UnsupportedError(');
    downBody.writeln("      'M$id is irreversible (codegen opted out).',");
    downBody.writeln('    );');
  } else if (forward.isEmpty && manualUnsafe.isEmpty) {
    downBody.writeln('    // No forward diffs to invert.');
    downBody.writeln('    // (Hand-roll if you need a rollback path.)');
  } else {
    for (final d in forward) {
      final String? inverse = inverseSqlFor(d);
      if (inverse == null) {
        downBody.writeln('    // No clean inverse for '
            '${d.type}; hand-roll if needed.');
        continue;
      }
      downBody.writeln('    // Inverse of ${d.type}.');
      if (d.severity == 'unsafe' ||
          d.type == 'createTable' ||
          d.type == 'addColumn') {
        downBody.writeln('    // WARNING: this rollback may destroy data.');
      }
      downBody.writeln('    exec(${dartRawString(inverse)});');
      downBody.writeln();
    }
    for (final d in manualUnsafe) {
      downBody.writeln('    // MANUAL REQUIRED: no clean inverse for '
          '${d.type} on ${d.tableName}.');
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
