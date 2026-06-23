/// .a + 10 — `d_rocket:migration` CLI:
///
/// Scaffolds a new migration file with the right
/// lexicographic ID, the canonical class name, and
/// pre-filled `up` / `down` stubs.
///
/// also adds commands to run migrations
/// against an actual database (status / run / rollback):
///
/// ```bash
/// # Add a new migration
/// dart run d_rocket:migration add create_users_table
///
/// # List all migrations in the current dir (or —dir)
/// dart run d_rocket:migration list
///
/// # Validate the migration history (orphans, gaps)
/// dart run d_rocket:migration doctor
///
/// # Print the current schema version of a DB
/// dart run d_rocket:migration status —db app.db
///
/// # Apply all pending migrations
/// dart run d_rocket:migration run —db app.db
///
/// # Migrate to a specific version (upgrade OR downgrade)
/// dart run d_rocket:migration run —db app.db —target 5
///
/// # Roll back the most recently applied migration
/// dart run d_rocket:migration rollback —db app.db
/// ```
///
/// Output: a `M003_create_users_table.dart` file
/// in the migrations dir (defaults to
/// `lib/db/migrations/`).
library;

import 'dart:io';

import 'package:d_rocket/src/cli/migration_check.dart';
import 'package:d_rocket/src/cli/migration_codegen.dart';
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

const String _kBanner = '''
┌─────────────────────────────────────────────┐
│ d_rocket migration scaffolder (Fase 9.8.a) │
│          + executor (Fase 10)              │
│          + checker  (Fase 11a)             │
└─────────────────────────────────────────────┘''';

Future<int> main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    return 1;
  }
  final String command = args.first;
  final List<String> rest = args.skip(1).toList();

  switch (command) {
    case 'add':
      if (rest.isEmpty) {
        stderr.writeln('Usage: migration add <name>');
        return 1;
      }
      return _addMigration(rest.first, _parseFlags(rest));
    case 'list':
      return _listMigrations();
    case 'doctor':
      return _doctor();
    case 'check':
      return _runCheck(_parseFlags(rest));
    case 'status':
      return _runStatus(_parseFlags(rest));
    case 'run':
      return _runMigrate(_parseFlags(rest));
    case 'rollback':
      return _runRollback(_parseFlags(rest));
    case 'help':
    case '--help':
    case '-h':
      _printUsage();
      return 0;
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      return 1;
  }
}

class _Flags {
  final String? dbPath;
  final int? target;
  final String? entitiesFile;
  final bool includeUnsafe;
  final bool irreversible;
  const _Flags({
    this.dbPath,
    this.target,
    this.entitiesFile,
    this.includeUnsafe = false,
    this.irreversible = false,
  });
}

///: minimal flag parser. Recognises
/// `—db <path>`, `—target <int>`, and
/// `—entities <dart_file>`. Unknown flags
/// are silently ignored (we keep it simple for the
/// MVP — a future PR can swap in `package:args`).
_Flags _parseFlags(List<String> args) {
  String? db;
  int? target;
  String? entities;
  bool includeUnsafe = false;
  bool irreversible = false;
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
      case '--include-unsafe':
        includeUnsafe = true;
        break;
      case '--irreversible':
        irreversible = true;
        break;
    }
  }
  return _Flags(
    dbPath: db,
    target: target,
    entitiesFile: entities,
    includeUnsafe: includeUnsafe,
    irreversible: irreversible,
  );
}

String _migrationsDir() {
  return Platform.environment['D_ROCKET_MIGRATIONS_DIR'] ?? 'lib/db/migrations';
}

void _printUsage() {
  stdout.writeln(_kBanner);
  stdout.writeln('''
Commands:
  add <name>          Create a new migration file
                      e.g. add create_users_table
                      Codegen mode (Phase 8.11): pass --db and
                      --entities to pre-fill up()/down() from the
                      schema diff:
                        add add_note_to_patients \\
                          --db app.db \\
                          --entities lib/db/entities.dart
                      --include-unsafe    also emit unsafe diffs
                                          in up() (default: skip)
                      --irreversible      skip the auto-inverse in
                                          down() (default: emit it)
  list                List all migrations in the migrations dir
  doctor              Validate the migration history
  check               Compute the schema diff and surface unsafe
                      operations. Exit 1 if any unsafe diffs
                      (CI-friendly; wire it into your pipeline).
                      Requires --db <path> AND --entities <file>.

Fase 10 — DB executor (require --db <path>):
  status --db <path>  Print the current schema version
  run --db <path>            Apply all pending migrations
  run --db <path> --target N Upgrade OR downgrade to vN
  rollback --db <path>       Roll back the most recent migration

Options (via env vars):
  D_ROCKET_MIGRATIONS_DIR   Where to look for / place files
                            (default: lib/db/migrations)

Note: `run` / `status` / `rollback` are MVP — they
connect to a raw SQLite file but do NOT auto-import
your migration classes. Use Db.open(strategy:)
programmatically for full functionality.

The `check` command generates a temp worker under
`.d_rocket/` that imports your --entities file, runs
the AutoMigrator against the --db SQLite file, and
prints the diff. Exit code is 1 if any unsafe diffs.
''');
}

int _nextMigrationId(Directory dir) {
  if (!dir.existsSync()) return 1;
  int maxId = 0;
  for (final f in dir.listSync()) {
    if (f is! File) continue;
    final name = f.uri.pathSegments.last;
    final m = RegExp(r'^M(\d+)_').firstMatch(name);
    if (m != null) {
      final n = int.tryParse(m.group(1)!) ?? 0;
      if (n > maxId) maxId = n;
    }
  }
  return maxId + 1;
}

Future<int> _addMigration(String name, _Flags flags) async {
  final dir = Directory(_migrationsDir());
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    stdout.writeln('📁 Created ${dir.path}/');
  }
  final int nextId = _nextMigrationId(dir);
  final String id = nextId.toString().padLeft(3, '0');
  final String className = cliNameToClassName(
    cliName: name,
    id: id,
  );
  final String fileName = 'M${id}_${cliNameToFileName(name)}.dart';
  final file = File('${dir.path}/$fileName');

  if (file.existsSync()) {
    stderr.writeln('❌ ${file.path} already exists');
    return 1;
  }

  // ── Codegen path (Phase 8.11) ─────────────
  // If the user passed --db + --entities, we
  // spawn the same worker as `check`, parse
  // the diffs, and feed them into the codegen
  // helpers. The emitted file has `up()`
  // pre-populated with the safe diffs and
  // `down()` pre-populated with the inverse.
  final String? dbPath = flags.dbPath;
  final String? entities = flags.entitiesFile;
  if (dbPath != null && entities != null) {
    return await _addMigrationCodegen(
      name: name,
      id: id,
      className: className,
      file: file,
      dbPath: dbPath,
      entities: entities,
      includeUnsafe: flags.includeUnsafe,
      irreversible: flags.irreversible,
    );
  }

  // ── Stub path (legacy behaviour) ──────────
  // No --db / --entities: emit the empty stub
  // so existing dev workflows are not broken.
  final String content = '''import 'package:d_rocket/d_rocket.dart';

/// .a — auto-generated by
/// `migration add $name`.
///
/// Edit the `up` body with your DDL. The `down`
/// body throws `UnsupportedError` by default — override
/// it for reversible migrations.
class $className extends MigrationBase {
  @override
  String get id => '$id';

  @override
  String get name => '$name';

  @override
  void up(MigrationExecutor exec) {
    // TODO: implement the up body.
    // Example:
    // exec(\\'\\'
    // CREATE TABLE users (
    // id INTEGER PRIMARY KEY AUTOINCREMENT,
    // name TEXT NOT NULL
    //)
    // \\'\\');
    throw UnimplementedError('M$id: implement up()');
  }

  @override
  void down(MigrationExecutor exec) {
    throw UnsupportedError(
      'M$id is irreversible by default. Override down() '
      'to enable rollback.',
    );
  }
}
''';

  file.writeAsStringSync(content);
  stdout.writeln('✅ Created ${file.path}');
  stdout.writeln('   id: $id, name: $name, class: $className');
  stdout.writeln('');
  stdout.writeln('ℹ️  Tip: pass --db <path> --entities <file> '
      'to pre-fill up() from the schema diff.');
  return 0;
}

/// Codegen path for `migration add`:
/// 1. Validate the entities file.
/// 2. Write the temp worker.
/// 3. Run the worker (same as `check`).
/// 4. Parse the diffs.
/// 5. Emit the file via [buildMigrationFileContent].
Future<int> _addMigrationCodegen({
  required String name,
  required String id,
  required String className,
  required File file,
  required String dbPath,
  required String entities,
  required bool includeUnsafe,
  required bool irreversible,
}) async {
  final String? err = validateEntitiesFile(entities);
  if (err != null) {
    stderr.writeln('Error: $err');
    return 2;
  }
  final Directory dRocketDir =
      Directory('.d_rocket')..createSync(recursive: true);
  final File workerFile = File('${dRocketDir.path}/check_worker.dart');
  workerFile.writeAsStringSync(buildCheckWorkerSource(entities));
  final String absDbPath = File(dbPath).absolute.path;

  stdout.writeln('🔎 Computing schema diff for codegen...');
  stdout.writeln('   db: $absDbPath');
  stdout.writeln('   entities: $entities');

  final ProcessResult result = await Process.run(
    'dart',
    <String>['run', workerFile.path, absDbPath],
    workingDirectory: Directory.current.path,
  );
  if (result.exitCode != 0) {
    stderr.writeln('❌ check_worker failed (exit ${result.exitCode}):');
    stderr.writeln(result.stderr);
    return result.exitCode;
  }
  final List<dynamic> raw;
  try {
    raw = extractCheckJsonPayload(result.stdout.toString());
  } on FormatException catch (e) {
    stderr.writeln('❌ unparseable JSON: $e');
    return 3;
  }
  final diffs = raw
      .map((dynamic e) =>
          CliSchemaDiff.fromJson((e as Map).cast<String, Object?>()))
      .toList(growable: false);

  final content = buildMigrationFileContent(
    className: className,
    id: id,
    name: name,
    diffs: diffs,
    options: CodegenOptions(
      includeUnsafe: includeUnsafe,
      irreversible: irreversible,
    ),
  );
  file.writeAsStringSync(content);
  final partitioned = partitionDiffsBySeverity(diffs);
  stdout.writeln('✅ Created ${file.path}');
  stdout.writeln('   id: $id, name: $name, class: $className');
  stdout.writeln('   ${partitioned.safe.length} safe diff(s) in up(), '
      '${partitioned.unsafe.length} unsafe diff(s) listed in header.');
  if (partitioned.unsafe.isNotEmpty) {
    stdout.writeln('');
    stdout.writeln('⚠️  Unsafe diffs are NOT auto-applied. '
        'Write a follow-up migration to handle them,');
    stdout.writeln('   or re-run with --include-unsafe to emit the '
        'unsafe SQL verbatim in up().');
  }
  return 0;
}

Future<int> _listMigrations() async {
  final dir = Directory(_migrationsDir());
  if (!dir.existsSync()) {
    stdout.writeln('(no migrations dir at ${dir.path})');
    return 0;
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => RegExp(r'^M\d+_').hasMatch(f.uri.pathSegments.last))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  if (files.isEmpty) {
    stdout.writeln('(no migrations)');
    return 0;
  }
  stdout.writeln('Migrations in ${dir.path}:');
  for (final f in files) {
    stdout.writeln('  ${f.uri.pathSegments.last}');
  }
  return 0;
}

Future<int> _doctor() async {
  final dir = Directory(_migrationsDir());
  if (!dir.existsSync()) {
    stdout.writeln('✅ (no migrations dir — clean state)');
    return 0;
  }
  final ids = <int>[];
  for (final f in dir.listSync().whereType<File>()) {
    final m = RegExp(r'^M(\d+)_').firstMatch(f.uri.pathSegments.last);
    if (m != null) ids.add(int.parse(m.group(1)!));
  }
  ids.sort();
  bool ok = true;
  for (int i = 0; i < ids.length; i++) {
    if (i > 0 && ids[i] != ids[i - 1] + 1) {
      stdout
          .writeln('⚠️  Gap between M${ids[i - 1].toString().padLeft(3, '0')} '
              'and M${ids[i].toString().padLeft(3, '0')}');
      ok = false;
    }
  }
  if (ok) {
    stdout.writeln('✅ MigrationBase history is contiguous '
        '(${ids.length} migrations).');
  }
  return ok ? 0 : 1;
}

// ─── Fase 11a: schema diff checker (`check`) ────────
//
// Computes the schema diff between the codegen-
// supplied entity metas (loaded from the user's
// `--entities` Dart file) and the actual schema
// in the SQLite file at `--db`. Exits 1 if any
// unsafe diffs are detected (CI-friendly).
//
// The pure helpers (flag parsing, worker-source
// templating, JSON extraction, entities-file
// validation, exit code computation) live in
// `package:d_rocket/src/cli/migration_check.dart`
// and are covered by unit tests. This function
// only orchestrates the side-effectful bits:
// subprocess spawn, file write, formatted print.
//
// Why a subprocess (not a direct call)?
// The user's entities live in their project
// graph (their app's pubspec deps). The CLI's
// own pubspec only knows about d_rocket +
// d_rocket_engine_sqlite. We can't statically
// import the user's code. The subprocess runs
// inside the user's project, so the user's
// pubspec resolves naturally.

Future<int> _runCheck(_Flags flags) async {
  final String? dbPath = flags.dbPath;
  final String? entities = flags.entitiesFile;
  if (dbPath == null) {
    stderr.writeln(
      'Error: check requires --db <path> (the SQLite file to compare against).',
    );
    return 2;
  }
  if (entities == null) {
    stderr.writeln(
      'Error: check requires --entities <dart_file> '
      '(a file that exports `List<EntityMeta> entityMetas = [...]`).',
    );
    return 2;
  }

  // Validate the entities file. The validation
  // helpers live in `migration_check.dart`.
  final String? err = validateEntitiesFile(entities);
  if (err != null) {
    stderr.writeln('Error: $err');
    return 2;
  }

  // Write the temp worker under `.d_rocket/`.
  // We use a `.d_rocket/` directory (gitignored
  // by convention) to avoid polluting the user's
  // project root.
  final Directory dRocketDir =
      Directory('.d_rocket')..createSync(recursive: true);
  final File workerFile = File('${dRocketDir.path}/check_worker.dart');
  workerFile.writeAsStringSync(buildCheckWorkerSource(entities));

  // Build the absolute db path so the worker
  // doesn't depend on its own cwd.
  final String absDbPath = File(dbPath).absolute.path;

  stdout.writeln('🔎 Computing schema diff...');
  stdout.writeln('   db: $absDbPath');
  stdout.writeln('   entities: $entities');

  // Run the worker.
  final ProcessResult result = await Process.run(
    'dart',
    <String>['run', workerFile.path, absDbPath],
    workingDirectory: Directory.current.path,
  );

  if (result.exitCode != 0) {
    stderr.writeln('❌ check_worker failed (exit ${result.exitCode}):');
    stderr.writeln(result.stderr);
    return result.exitCode;
  }

  // Extract the JSON between the markers
  // (helper lives in migration_check.dart).
  final List<dynamic> raw;
  try {
    raw = extractCheckJsonPayload(result.stdout.toString());
  } on FormatException catch (e) {
    stderr.writeln('❌ check_worker emitted an unparseable '
        'JSON payload: $e');
    stderr.writeln('stdout was:\n${result.stdout}');
    return 3;
  }

  // Summarise.
  final List<Map<String, Object?>> diffs = raw
      .map((dynamic e) => (e as Map).cast<String, Object?>())
      .toList(growable: false);

  final int safeCount =
      diffs.where((d) => d['severity'] == 'safe').length;
  final int unsafeCount =
      diffs.where((d) => d['severity'] == 'unsafe').length;

  if (diffs.isEmpty) {
    stdout.writeln('✅ Schema is in sync (no diffs).');
    return 0;
  }

  stdout.writeln('');
  stdout.writeln('Found ${diffs.length} diff(s) '
      '($safeCount safe, $unsafeCount unsafe):');
  for (final d in diffs) {
    final String sev = d['severity'] as String;
    final String type = d['type'] as String;
    final String table = d['tableName'] as String;
    final String? col = d['columnName'] as String?;
    final String? newCol = d['newColumnName'] as String?;
    final String sql = d['sql'] as String;
    final String reason = d['reason'] as String;
    final String target = col == null
        ? table
        : (newCol == null ? '$table.$col' : '$table.$col -> $newCol');
    final String tag = sev == 'unsafe' ? '❌ UNSAFE' : '✓  SAFE  ';
    stdout.writeln('  $tag  $type on $target');
    stdout.writeln('            sql:    $sql');
    stdout.writeln('            reason: $reason');
  }

  stdout.writeln('');
  if (unsafeCount > 0) {
    stdout.writeln(
      '❌ $unsafeCount unsafe diff(s) found. '
      'Resolve before merging: write a hand-rolled migration that '
      'performs the unsafe operation explicitly (auto-migrator '
      'does NOT auto-apply unsafe diffs).',
    );
    return 1;
  }
  stdout.writeln(
    '✓ $safeCount safe diff(s); auto-migrator will apply them on next '
    'Db.open(autoMigrate: true).',
  );
  return 0;
}

// ───: DB executor (status / run / rollback) ───────
//
// MVP scope: the CLI connects to a raw SQLite file
// (via `SqliteQueryProvider.file`) and runs a stripped
// `MigrationRunner` against it. It does NOT auto-import
// your migration classes — for that, use
// `Db.open(strategy: ...)` programmatically.
//
// The runner here is a thin shim that wraps the raw
// provider's `execute` / `select` into the
// `MigrationExecutor` / `MigrationSelector` typedefs.

class _RawSqliteRunner {
  _RawSqliteRunner(String path) {
    _provider = SqliteQueryProvider.file(path);
  }
  late final SqliteQueryProvider _provider;

  Future<int> currentVersion() async {
    return _buildRunner().currentVersionAsync();
  }

  Future<List<AppliedMigration>> applied() async {
    return _buildRunner().appliedAsync();
  }

  /// Applies the `exec` callback as a single
  /// migration. The CLI uses this for `run —target N`
  /// to perform a no-op-migration run (the user's
  /// strategy is what actually picks the subset).
  Future<int> upgradeTo(int target) async {
    // Without the migration classes on hand, we
    // can't pick the subset to run. We just print
    // the current state and the target.
    final from = await currentVersion();
    stdout.writeln(
      'current: v$from, target: v$target '
      '(${target > from ? "upgrade" : "downgrade"})',
    );
    stdout.writeln(
      '⚠️  This CLI MVP does NOT load your migration classes. '
      'Use `Db.open(strategy: MigrationStrategy(...))` '
      'programmatically to actually apply migrations.',
    );
    return from == target ? 0 : 1;
  }

  MigrationRunner _buildRunner() {
    return MigrationRunner(
      createExecutor: () => (String sql, [List<Object?>? binds]) {
        if (binds != null && binds.isNotEmpty) {
          _provider.execute(sql, binds);
        } else {
          _provider.execute(sql);
        }
      },
      createSelector: () => (String sql, [List<Object?>? binds]) {
        if (binds != null && binds.isNotEmpty) {
          return _provider.selectWithBinds(sql, binds);
        }
        return _provider.select(sql);
      },
      createAsyncExecutor: () => (String sql, [List<Object?>? binds]) async {
        if (binds != null && binds.isNotEmpty) {
          _provider.execute(sql, binds);
        } else {
          _provider.execute(sql);
        }
      },
      createAsyncSelector: () => (String sql, [List<Object?>? binds]) async {
        if (binds != null && binds.isNotEmpty) {
          return _provider.selectWithBinds(sql, binds);
        }
        return _provider.select(sql);
      },
    );
  }

  Future<void> close() async {
    await _provider.disposeAsync();
  }
}

Future<int> _runStatus(_Flags f) async {
  if (f.dbPath == null) {
    stderr.writeln('Error: --db <path> is required');
    return 2;
  }
  final runner = _RawSqliteRunner(f.dbPath!);
  try {
    final v = await runner.currentVersion();
    stdout.writeln('schema version: v$v');
    final list = await runner.applied();
    if (list.isEmpty) {
      stdout.writeln('(no migrations applied yet)');
    } else {
      stdout.writeln('');
      stdout
          .writeln('  id    version  name                          applied_at');
      stdout.writeln(
          '  ----  -------  ----------------------------  -----------------');
      for (final m in list) {
        stdout.writeln(
          '  ${m.id.padRight(4)}  '
          '${(m.version ?? 0).toString().padLeft(7)}  '
          '${m.name.padRight(28)}  '
          '${m.appliedAt.toIso8601String()}',
        );
      }
    }
    return 0;
  } finally {
    await runner.close();
  }
}

Future<int> _runMigrate(_Flags f) async {
  if (f.dbPath == null) {
    stderr.writeln('Error: --db <path> is required');
    return 2;
  }
  final runner = _RawSqliteRunner(f.dbPath!);
  try {
    if (f.target != null) {
      final code = await runner.upgradeTo(f.target!);
      return code;
    }
    // No target: just print the current state.
    final v = await runner.currentVersion();
    stdout.writeln('current: v$v');
    stdout.writeln(
      '⚠️  Apply all pending migrations programmatically via '
      '`Db.open(strategy: MigrationStrategy(...))`. '
      'See the README for the full pattern.',
    );
    return 0;
  } finally {
    await runner.close();
  }
}

Future<int> _runRollback(_Flags f) async {
  if (f.dbPath == null) {
    stderr.writeln('Error: --db <path> is required');
    return 2;
  }
  stderr.writeln(
    '⚠️  `rollback` requires the migration classes on hand to '
    'call `MigrationBase.down()`. Use '
    '`Db.open(strategy: ...)` programmatically, or '
    '`run --db <path> --target N` to downgrade to vN.',
  );
  return 0;
}
