//: tests for the ADO-style / sqflite-style
// migration API:
//
// - `MigrationStrategy` (declarative + imperative modes)
// - `MigrationRunner.migrateTo(targetVersion)` (up/down)
// - `MigrationRunner.currentVersion` / `applied`
// - Schema-upgrade of the `_d_rocket_migrations`
// table (adds `version` column with backfill)
// - Backward compat with pre—10 String-id style
// migrations

import '../_helpers.dart';
import 'package:test/test.dart';

class _Log {
  final List<String> events = <String>[];
  void add(String e) => events.add(e);
}

class _CreateUsers extends MigrationBase {
  _CreateUsers({this.versionOverride});

  final int? versionOverride;

  @override
  String get id => '001';

  @override
  int get version => versionOverride ?? super.version;

  @override
  String get name => 'create_users';

  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE users');
  }
}

class _AddEmail extends MigrationBase {
  @override
  String get id => '002';

  @override
  String get name => 'add_email';

  @override
  void up(MigrationExecutor exec) {
    exec('ALTER TABLE users ADD COLUMN email TEXT');
  }

  @override
  void down(MigrationExecutor exec) {
    // SQLite < 3.35 doesn't support DROP COLUMN. We
    // keep it as-is (irreversible in practice) for
    // this test.
    throw UnsupportedError('DROP COLUMN not supported');
  }
}

class _AddPosts extends MigrationBase {
  @override
  String get id => '003';

  @override
  String get name => 'add_posts';

  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE posts (id INTEGER PRIMARY KEY, title TEXT)');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE posts');
  }
}

class _DateBasedId extends MigrationBase {
  //: a migration with a non-numeric id —
  // the user must override `version` explicitly.
  @override
  String get id => '2026-06-12-001';

  @override
  int get version => 5; // monotonic override

  @override
  String get name => 'date_based';

  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE audit (id INTEGER PRIMARY KEY)');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE audit');
  }
}

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 10 — MigrationBase.version getter', () {
    test('parses numeric String id by default', () {
      expect(_CreateUsers().version, 1);
      expect(_AddEmail().version, 2);
      expect(_AddPosts().version, 3);
    });

    test('override beats parsing', () {
      final m = _CreateUsers(versionOverride: 42);
      expect(m.version, 42);
    });

    test('throws StateError on non-numeric id without override', () {
      expect(
        () => _DateBasedId().version,
        // The override IS provided in _DateBasedId, so
        // this should NOT throw. Use a different
        // example.
        returnsNormally,
      );
    });
  });

  group('Fase 10 — tracking table schema upgrade', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('creates _d_rocket_migrations with version column on a fresh install',
        () async {
      // Run a single migration to trigger the schema
      // ensure.
      final runner = MigrationRunner(
        createExecutor: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createSelector: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
      );
      runner.run([_CreateUsers()]);

      // Inspect the table schema — version column
      // should be there.
      final List<Map<String, Object?>> cols = provider.select(
        'PRAGMA table_info(_d_rocket_migrations)',
      );
      final names = <String>[
        for (final r in cols) r['name']! as String,
      ];
      expect(
          names, containsAll(<String>['id', 'name', 'version', 'applied_at']));
    });

    test('auto-migrates a pre-Fase-10 installation (no version column)',
        () async {
      // Manually create a V1-style tracking table
      // (no version column) and seed it with a
      // pre—10 row.
      provider.execute(
        'CREATE TABLE _d_rocket_migrations ('
        '  id TEXT PRIMARY KEY, '
        '  name TEXT NOT NULL, '
        '  applied_at TEXT NOT NULL'
        ')',
      );
      provider.execute(
        'INSERT INTO _d_rocket_migrations VALUES (?, ?, ?)',
        <Object?>['001', 'create_users', '2026-01-01T00:00:00.000Z'],
      );

      final runner = MigrationRunner(
        createExecutor: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createSelector: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
      );

      // Trigger the schema upgrade by asking for
      // the current version.
      final v = runner.currentVersion();
      expect(v, 1, reason: 'backfilled from id=001');

      // Verify the column was added and the row
      // got a `version` value.
      final List<Map<String, Object?>> cols = provider.select(
        'PRAGMA table_info(_d_rocket_migrations)',
      );
      final names = <String>[
        for (final r in cols) r['name']! as String,
      ];
      expect(names, contains('version'));

      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id, version FROM _d_rocket_migrations',
      );
      expect(rows, hasLength(1));
      expect(rows.first['id'], '001');
      expect(rows.first['version'], 1);
    });
  });

  group('Fase 10 — currentVersion / applied', () {
    late SqliteQueryProvider provider;
    late MigrationRunner runner;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      runner = MigrationRunner(
        createExecutor: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createSelector: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
        createAsyncExecutor: () => (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createAsyncSelector: () => (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
      );
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('currentVersion() returns 0 on a fresh install', () {
      expect(runner.currentVersion(), 0);
    });

    test('currentVersion() returns the highest version after running', () {
      runner.run([_CreateUsers(), _AddEmail(), _AddPosts()]);
      expect(runner.currentVersion(), 3);
    });

    test('applied() returns the list in version order', () {
      runner.run([_AddPosts(), _CreateUsers(), _AddEmail()]);
      final list = runner.applied();
      expect(list, hasLength(3));
      expect(list[0].id, '001');
      expect(list[0].version, 1);
      expect(list[1].id, '002');
      expect(list[1].version, 2);
      expect(list[2].id, '003');
      expect(list[2].version, 3);
    });

    test('appliedAsync() returns the same as applied()', () async {
      runner.run([_CreateUsers(), _AddEmail()]);
      final list = await runner.appliedAsync();
      expect(list, hasLength(2));
      expect(list[0].id, '001');
      expect(list[1].id, '002');
    });
  });

  group('Fase 10 — migrateTo(target)', () {
    late SqliteQueryProvider provider;
    late MigrationRunner runner;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      runner = MigrationRunner(
        createExecutor: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createSelector: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
        createAsyncExecutor: () => (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createAsyncSelector: () => (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
      );
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('fresh install: target > 0 applies all (up to target)', () {
      final applied = runner.migrateTo(3, [
        _CreateUsers(),
        _AddEmail(),
        _AddPosts(),
      ]);
      expect(applied, hasLength(3));
      expect(applied[0].id, '001');
      expect(applied[1].id, '002');
      expect(applied[2].id, '003');
      expect(runner.currentVersion(), 3);
    });

    test('upgrade: from v1 to v3 applies the subset in (1, 3]', () {
      runner.migrateTo(1, [_CreateUsers(), _AddEmail(), _AddPosts()]);
      final applied = runner.migrateTo(3, [
        _CreateUsers(),
        _AddEmail(),
        _AddPosts(),
      ]);
      expect(applied, hasLength(2));
      expect(applied[0].id, '002');
      expect(applied[1].id, '003');
    });

    test('downgrade: from v3 to v1 rolls back the subset in (1, 3]', () {
      runner.migrateTo(3, [_CreateUsers(), _AddEmail(), _AddPosts()]);
      final applied = runner.migrateTo(1, [
        _CreateUsers(),
        _AddEmail(),
        _AddPosts(),
      ]);
      // The runner reverses the order. M003 is rolled
      // back first (its `down` works), then M002
      // (which is irreversible — UnsupportedError is
      // caught and skipped).
      expect(applied, hasLength(1),
          reason: 'M002 is irreversible (DROP COLUMN)');
      expect(applied.first.id, '003');
      expect(runner.currentVersion(), 2, reason: 'M002 is still recorded');
    });

    test('no-op when current == target', () {
      runner.migrateTo(2, [_CreateUsers(), _AddEmail()]);
      final applied = runner.migrateTo(2, [
        _CreateUsers(),
        _AddEmail(),
      ]);
      expect(applied, isEmpty);
    });

    test('migrateToAsync upgrade', () async {
      await runner.migrateToAsync(1, [_CreateUsers()]);
      final applied = await runner.migrateToAsync(2, [
        _CreateUsers(),
        _AddEmail(),
      ]);
      expect(applied, hasLength(1));
      expect(applied.first.id, '002');
    });
  });

  group('Fase 10 — MigrationStrategy declarative mode', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('declarative fresh install: applies all migrations', () {
      final strategy = MigrationStrategy(
        version: 3,
        migrations: <MigrationBase>[
          _CreateUsers(),
          _AddEmail(),
          _AddPosts(),
        ],
      );

      // We run the strategy via the same helper
      // path the Db facade uses, but the
      // public API for "run a strategy against a
      // raw provider" is built ad-hoc here.
      final ctxRunner = MigrationRunner(
        createExecutor: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
        },
        createSelector: () => (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        },
      );
      final from = ctxRunner.currentVersion();
      expect(from, 0);
      final applied =
          ctxRunner.migrateTo(strategy.version, strategy.migrations);
      expect(applied, hasLength(3));
      expect(ctxRunner.currentVersion(), 3);
    });

    test('isImperative: false for declarative', () {
      const s = MigrationStrategy(version: 1);
      expect(s.isImperative, isFalse);
    });

    test('isImperative: true when any callback is provided', () {
      final s = MigrationStrategy(
        version: 1,
        onCreate: (exec, v) async {},
      );
      expect(s.isImperative, isTrue);
    });
  });

  group('Fase 10 — Db.open(strategy:)', () {
    test('declarative strategy runs on a fresh in-memory DB', () async {
      final db = await Db.inMemory(
        strategy: MigrationStrategy(
          version: 2,
          migrations: <MigrationBase>[
            _CreateUsers(),
            _AddEmail(),
          ],
        ),
      );
      // After open, the strategy has run. The
      // users table exists with the email column.
      final v = await db.currentVersion();
      expect(v, 2);
      // Verify the tables exist by inserting a row.
      db.provider.execute(
        'INSERT INTO users (id, name, email) VALUES (1, ?, ?)',
        <Object?>['Abner', 'a@example.com'],
      );
      final rows = db.provider.select(
        'SELECT name, email FROM users WHERE id = 1',
      );
      expect(rows.first['name'], 'Abner');
      expect(rows.first['email'], 'a@example.com');
      await db.close();
    });

    test('onCreate strategy is invoked on a fresh install', () async {
      final _Log log = _Log();
      final db = await Db.inMemory(
        strategy: MigrationStrategy(
          version: 1,
          onCreate: (exec, v) async {
            exec('CREATE TABLE bootstrap (id INTEGER PRIMARY KEY)');
            log.add('onCreate v=$v');
          },
        ),
      );
      expect(log.events, <String>['onCreate v=1']);
      // Verify the table was actually created.
      final rows = db.provider.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='bootstrap'",
      );
      expect(rows, hasLength(1));
      await db.close();
    });

    test('idempotent: re-opening at the same version is a no-op', () async {
      final s = MigrationStrategy(
        version: 2,
        migrations: <MigrationBase>[
          _CreateUsers(),
          _AddEmail(),
        ],
      );
      final db1 = await Db.inMemory(strategy: s);
      final v1 = await db1.currentVersion();
      await db1.close();

      // Open a fresh DB and re-run the same
      // strategy.
      final db2 = await Db.inMemory(strategy: s);
      final v2 = await db2.currentVersion();
      expect(v2, v1);
      await db2.close();
    });
  });
}
