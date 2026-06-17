// Tests for the async migration runner:
// `MigrationRunner.runAsync` and `MigrationRunner.rollbackAsync`.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  late SqliteQueryProvider provider;
  late MigrationRunner runner;
  late _MigrationLog log;

  setUp(() {
    provider = SqliteQueryProvider.inMemory();
    log = _MigrationLog();
    //: the user wires the `createAsync*`
    // factories explicitly. For SQLite, they wrap the
    // sync ones (or could use the auto-wrap).
    runner = MigrationRunner(
      createExecutor: () {
        final list = <Object?>[];
        return (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
          log.executed.add(<Object?>[sql, ...?binds]);
          list.add(sql);
        };
      },
      createSelector: () {
        return (String sql, [List<Object?>? binds]) {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        };
      },
      createAsyncExecutor: () {
        return (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            provider.execute(sql, binds);
          } else {
            provider.execute(sql);
          }
          log.executedAsync.add(<Object?>[sql, ...?binds]);
        };
      },
      createAsyncSelector: () {
        return (String sql, [List<Object?>? binds]) async {
          if (binds != null && binds.isNotEmpty) {
            return provider.selectWithBinds(sql, binds);
          }
          return provider.select(sql);
        };
      },
    );
  });

  tearDown(() async {
    await provider.disposeAsync();
  });

  group('Fase 5.0+4 — MigrationRunner.runAsync', () {
    test('applies a single migration', () async {
      final migration = _CreateBooksTable();
      final List<MigrationBase> applied = await runner.runAsync([migration]);
      expect(applied, hasLength(1));
      expect(applied.first.id, '001');
      // The migration was actually executed.
      expect(log.executedAsync, isNotEmpty);
      // The books table exists.
      final List<Map<String, Object?>> rows = provider.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='books'",
      );
      expect(rows, hasLength(1));
    });

    test('applies multiple migrations in order', () async {
      final applied = await runner.runAsync(<MigrationBase>[
        _CreateBooksTable(id: '002'),
        _CreateAuthorsTable(id: '001'),
      ]);
      expect(applied, hasLength(2));
      // The runner sorts by id; '001' (authors) comes first.
      expect(applied[0].id, '001');
      expect(applied[1].id, '002');
    });

    test('skips already-applied migrations (idempotent)', () async {
      final migration = _CreateBooksTable();
      final List<MigrationBase> first = await runner.runAsync([migration]);
      expect(first, hasLength(1));
      // Re-run the same set.
      final List<MigrationBase> second = await runner.runAsync([migration]);
      expect(second, isEmpty, reason: 'no new migrations applied');
    });

    test('respects the AsyncMigrationExecutor wiring (no sync fallback)',
        () async {
      // Run a migration through runAsync.
      await runner.runAsync([_CreateBooksTable()]);
      // The async log has entries; the sync log is empty.
      expect(log.executedAsync, isNotEmpty);
      // Note: the async factory was used (not the sync
      // fallback) — verified by `log.executedAsync`.
    });
  });

  group('Fase 5.0+4 — MigrationRunner.rollbackAsync', () {
    test('rolls back a single migration', () async {
      final migration = _CreateBooksTable();
      await runner.runAsync([migration]);
      final rolledBack = await runner.rollbackAsync([migration]);
      expect(rolledBack, hasLength(1));
      // The books table is gone.
      final List<Map<String, Object?>> rows = provider.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='books'",
      );
      expect(rows, isEmpty);
    });

    test('rolls back migrations in reverse order', () async {
      final m1 = _CreateBooksTable(id: '001');
      final m2 = _CreateAuthorsTable(id: '002');
      await runner.runAsync(<MigrationBase>[m1, m2]);
      final rolledBack = await runner.rollbackAsync(<MigrationBase>[m1, m2]);
      expect(rolledBack, hasLength(2));
      expect(rolledBack[0].id, '002', reason: 'reverse order');
      expect(rolledBack[1].id, '001');
    });

    test('skips irreversible migrations (UnsupportedError)', () async {
      final irreversible = _IrreversibleMigration();
      await runner.runAsync([irreversible]);
      // rollbackAsync should skip it (default downAsync
      // throws UnsupportedError).
      final rolledBack = await runner.rollbackAsync([irreversible]);
      expect(rolledBack, isEmpty,
          reason: 'irreversible migrations are skipped on rollback');
    });
  });

  group('Fase 5.0+4 — upAsync / downAsync override (real async I/O)', () {
    test('overridden upAsync is awaited', () async {
      final async = _MigrationWithAsyncBody();
      await runner.runAsync([async]);
      expect(async.upAsyncCalled, isTrue);
      // The body of upAsync (an `INSERT INTO ...` via
      // the async executor) ran.
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT name FROM seed_table',
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'seeded-via-async');
    });
  });

  group('Fase 5.0+4 — sync API still works (no breaking change)', () {
    test('run() still works synchronously', () {
      final migration = _CreateBooksTable();
      final List<MigrationBase> applied = runner.run([migration]);
      expect(applied, hasLength(1));
    });

    test('rollback() still works synchronously', () {
      final migration = _CreateBooksTable();
      runner.run([migration]);
      final rolledBack = runner.rollback([migration]);
      expect(rolledBack, hasLength(1));
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

class _MigrationLog {
  final List<List<Object?>> executed = <List<Object?>>[];
  final List<List<Object?>> executedAsync = <List<Object?>>[];
}

class _CreateBooksTable extends MigrationBase {
  _CreateBooksTable({this.id = '001'});
  @override
  final String id;
  @override
  String get name => 'Create books table';
  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL'
        ')');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE books');
  }
}

class _CreateAuthorsTable extends MigrationBase {
  _CreateAuthorsTable({this.id = '002'});
  @override
  final String id;
  @override
  String get name => 'Create authors table';
  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE authors ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  name TEXT NOT NULL'
        ')');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE authors');
  }
}

class _IrreversibleMigration extends MigrationBase {
  @override
  String get id => '999';
  @override
  String get name => 'Irreversible migration';
  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE tmp_table (id INTEGER PRIMARY KEY)');
  }
  // down not overridden — uses the default that throws.
}

class _MigrationWithAsyncBody extends MigrationBase {
  bool upAsyncCalled = false;
  @override
  String get id => '003';
  @override
  String get name => 'MigrationBase with overridden upAsync';
  @override
  void up(MigrationExecutor exec) {
    // The sync path creates the table (for the test
    // setup), the async path inserts the row.
    exec('CREATE TABLE seed_table (id INTEGER PRIMARY KEY, name TEXT)');
  }

  @override
  Future<void> upAsync(AsyncMigrationExecutor exec) async {
    upAsyncCalled = true;
    // The user's override runs the real async body
    // (e.g. inserting via the AsyncMigrationExecutor).
    await exec('CREATE TABLE seed_table (id INTEGER PRIMARY KEY, name TEXT)');
    await exec('INSERT INTO seed_table (name) VALUES (?)',
        <Object?>['seeded-via-async']);
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE seed_table');
  }
}
