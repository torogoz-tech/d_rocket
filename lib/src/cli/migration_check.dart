/// 2.0.0 — `migration check` (Fase 11a):
/// pure helpers extracted from `bin/migration.dart`
/// for unit testing.
///
/// The CLI's `check` subcommand computes the
/// schema diff between the codegen-supplied
/// entity metas and the actual schema in a
/// SQLite DB. It writes a temp worker under
/// `.d_rocket/`, runs it as a `dart run`
/// subprocess, parses the JSON diff between
/// `DR_CHECK_JSON_BEGIN` / `DR_CHECK_JSON_END`
/// markers, and prints a human-readable
/// summary.
///
/// This library holds the pure helpers (flag
/// parsing, worker-source templating, JSON
/// extraction, entities-file validation, exit
/// code computation). The side-effectful
/// orchestration (subprocess spawn, file
/// write) stays in `bin/migration.dart` and is
/// covered by manual smoke tests.
library;

import 'dart:convert';
import 'dart:io';

/// Flag bundle for the `check` subcommand.
/// Exposed for tests; the CLI uses the same
/// struct via `_Flags` (kept identical to
/// preserve binary compatibility).
class CheckFlags {
  final String? dbPath;
  final int? target;
  final String? entitiesFile;
  const CheckFlags({this.dbPath, this.target, this.entitiesFile});
}

/// Marker lines bracketing the JSON payload
/// emitted by the temp worker. The CLI uses
/// these to extract the JSON from a stream that
/// may include compile / runtime stderr noise.
const String kCheckJsonBegin = 'DR_CHECK_JSON_BEGIN';
const String kCheckJsonEnd = 'DR_CHECK_JSON_END';

/// Parses the CLI flags for the `check`
/// subcommand. Recognises `--db <path>`,
/// `--target <int>`, `--entities <dart_file>`
/// (and short form `-e`). Unknown flags are
/// silently ignored (MVP; a future PR can
/// swap in `package:args`).
///
/// Exits the process with code 2 on missing
/// required argument (matches the behaviour
/// of the rest of the CLI).
CheckFlags parseCheckFlags(List<String> args) {
  String? db;
  int? target;
  String? entities;
  for (int i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--db':
        if (i + 1 >= args.length) {
          stderr.writeln('Error: --db requires a path argument');
          exit(2);
        }
        db = args[i + 1];
        i++;
        break;
      case '--target':
        if (i + 1 >= args.length) {
          stderr.writeln('Error: --target requires an int argument');
          exit(2);
        }
        target = int.tryParse(args[i + 1]);
        if (target == null) {
          stderr.writeln(
            'Error: --target value "${args[i + 1]}" is not an int',
          );
          exit(2);
        }
        i++;
        break;
      case '--entities':
      case '-e':
        if (i + 1 >= args.length) {
          stderr.writeln(
            'Error: --entities requires a Dart file path argument',
          );
          exit(2);
        }
        entities = args[i + 1];
        i++;
        break;
    }
  }
  return CheckFlags(dbPath: db, target: target, entitiesFile: entities);
}

/// The temp worker template. The CLI writes it
/// to `.d_rocket/check_worker.dart` and runs
/// `dart run` on it. The worker imports the
/// user's `--entities` file (relative path) and
/// the d_rocket + SQLite engine packages
/// (resolved from the user's project graph).
String buildCheckWorkerSource(String entitiesImport) {
  return '''
import 'dart:convert';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

import '$entitiesImport' as user_entities;

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: check_worker <db_path>');
    exit(2);
  }
  final dbPath = args[0];
  final provider = SqliteQueryProvider.file(dbPath);
  try {
    final migrator = AutoMigrator(
      provider: provider,
      entityMetas: user_entities.entityMetas,
    );
    final diffs = await migrator.computePendingDiff();
    final payload = diffs
        .map((d) => <String, Object?>{
              'severity': d.severity.name,
              'type': d.type.name,
              'tableName': d.tableName,
              if (d.columnName != null) 'columnName': d.columnName,
              if (d.newColumnName != null)
                'newColumnName': d.newColumnName,
              'sql': d.sql,
              'reason': d.reason,
            })
        .toList(growable: false);
    stdout.writeln('$kCheckJsonBegin');
    stdout.writeln(jsonEncode(payload));
    stdout.writeln('$kCheckJsonEnd');
  } catch (e, st) {
    stderr.writeln('check_worker error: \$e');
    stderr.writeln(st);
    exit(3);
  } finally {
    await provider.disposeAsync();
  }
}
''';
}

/// Extracts the JSON payload between the
/// `$kCheckJsonBegin` / `$kCheckJsonEnd`
/// markers. Throws [FormatException] if either
/// marker is missing, or if the payload is not
/// valid JSON.
List<dynamic> extractCheckJsonPayload(String stdoutStr) {
  final int beginIdx = stdoutStr.indexOf(kCheckJsonBegin);
  final int endIdx = stdoutStr.indexOf(kCheckJsonEnd);
  if (beginIdx < 0) {
    throw FormatException(
      'Missing $kCheckJsonBegin marker in worker output',
    );
  }
  if (endIdx < 0 || endIdx <= beginIdx) {
    throw FormatException(
      'Missing $kCheckJsonEnd marker after $kCheckJsonBegin',
    );
  }
  final String jsonStr = stdoutStr
      .substring(beginIdx + kCheckJsonBegin.length, endIdx)
      .trim();
  return jsonDecode(jsonStr) as List<dynamic>;
}

/// Validates the user's entities file. Returns
/// `null` if the file is usable, or a
/// human-readable error string otherwise. The
/// CLI surfaces the error to stderr before
/// exiting 2.
String? validateEntitiesFile(String path) {
  final File f = File(path);
  if (!f.existsSync()) {
    return 'entities file "$path" does not exist '
        '(cwd: ${Directory.current.path}).';
  }
  final String src = f.readAsStringSync();
  if (!src.contains('entityMetas')) {
    return 'entities file "$path" does not declare '
        '`entityMetas` (the worker imports '
        '`user_entities.entityMetas` from it). Add '
        'a top-level '
        '`final List<EntityMeta> entityMetas = [...]`.';
  }
  return null;
}

/// Computes the exit code from a list of
/// diffs. Exits 0 when there are no unsafe
/// diffs; exits 1 when any diff has
/// `severity == 'unsafe'`. CI-friendly: wire
/// this into the pipeline as a check.
int exitCodeForDiffs(List<Map<String, Object?>> diffs) {
  final int unsafeCount =
      diffs.where((d) => d['severity'] == 'unsafe').length;
  return unsafeCount > 0 ? 1 : 0;
}