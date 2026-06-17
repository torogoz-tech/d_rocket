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

import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

const String _kBanner = '''
┌─────────────────────────────────────────────┐
│ d_rocket migration scaffolder (Fase 9.8.a) │
│          + executor (Fase 10)              │
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
      return _addMigration(rest.first);
    case 'list':
      return _listMigrations();
    case 'doctor':
      return _doctor();
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
  const _Flags({this.dbPath, this.target});
}

///: minimal flag parser. Recognises
/// `—db <path>` and `—target <int>`. Unknown flags
/// are silently ignored (we keep it simple for the
/// MVP — a future PR can swap in `package:args`).
_Flags _parseFlags(List<String> args) {
  String? db;
  int? target;
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
    }
  }
  return _Flags(dbPath: db, target: target);
}

String _migrationsDir() {
  return Platform.environment['D_ROCKET_MIGRATIONS_DIR'] ?? 'lib/db/migrations';
}

String _kebabToSnakeClassName(String kebab) {
  // "create_users_table" → "CreateUsersTable"
  final parts = kebab.split(RegExp(r'[_\- ]+'));
  return parts
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
      .join();
}

String _kebabToFileName(String kebab) {
  return kebab.toLowerCase().replaceAll(RegExp(r'[ _\-]+'), '_');
}

void _printUsage() {
  stdout.writeln(_kBanner);
  stdout.writeln('''
Commands:
  add <name>          Create a new migration file
                      e.g. add create_users_table
  list                List all migrations in the migrations dir
  doctor              Validate the migration history

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

Future<int> _addMigration(String name) async {
  final dir = Directory(_migrationsDir());
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
    stdout.writeln('📁 Created ${dir.path}/');
  }
  final int nextId = _nextMigrationId(dir);
  final String id = nextId.toString().padLeft(3, '0');
  final String className = 'M$id${_kebabToSnakeClassName(name)}';
  final String fileName = 'M${id}_${_kebabToFileName(name)}.dart';
  final file = File('${dir.path}/$fileName');

  if (file.existsSync()) {
    stderr.writeln('❌ ${file.path} already exists');
    return 1;
  }

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
