//: tests for `DbContext.migrate` /
// `migrateAsync`. The user overrides `migrations` on
// the context, then calls `migrate` at startup. The
// internal `_d_rocket_migrations` table tracks which
// migrations have already been applied (idempotent
// across re-runs).

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group(
      'Fase 5.3 — ctx.migrateAsync() async path (SQLite as AsyncQueryProvider)',
      () {
    late SqliteQueryProvider provider;
    late _TestContextAsync ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      ctx = _TestContextAsync(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('migrateAsync() applies all pending migrations in order', () async {
      ctx.migrations.add(_$001InitialSchema());
      ctx.migrations.add(_$002AddBookPrice());

      final List<MigrationBase> applied = await ctx.migrateAsync();
      expect(applied, hasLength(2));
      // The table exists.
      final List<Map<String, Object?>> rows = provider.select(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'books'",
      );
      expect(rows, hasLength(1));
    });

    test('migrateAsync() throws on a context without an async provider',
        () async {
      // The `_TestContextSync` has no `asyncProvider`.
      final _TestContextSync ctxSync = _TestContextSync();
      expect(
        () async => await ctxSync.migrateAsync(),
        throwsA(isA<StateError>()),
      );
    });

    test('migrate() throws on a context with an async provider', () {
      // The `_TestContextAsync` has both sync and async
      // providers (async wins). Calling sync `migrate`
      // throws.
      expect(() => ctx.migrate(), throwsA(isA<UnsupportedError>()));
    });
  });

  group('Fase 5.3 — ctx.rollback() / rollbackAsync()', () {
    late SqliteQueryProvider provider;
    late _TestContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      ctx = _TestContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('rollback() reverses migrations in order (002 → 001)', () async {
      ctx.migrations.add(_$001InitialSchema());
      ctx.migrations.add(_$002AddBookPrice());
      await ctx.migrateAsync();
      final List<MigrationBase> rolledBack = await ctx.rollbackAsync();
      expect(rolledBack, hasLength(2));
      expect(rolledBack[0].id, '002', reason: 'most recent first');
      expect(rolledBack[1].id, '001');
      // The `_d_rocket_migrations` table is empty.
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id FROM _d_rocket_migrations',
      );
      expect(rows, isEmpty);
      // The `price` column is gone (rolled back).
      final List<Map<String, Object?>> columns = provider.select(
        'PRAGMA table_info(books)',
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> c in columns) c['name']! as String,
      };
      expect(names, isNot(contains('price')));
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

class _$001InitialSchema extends MigrationBase {
  _$001InitialSchema();
  @override
  String get id => '001';
  @override
  String get name => 'Initial schema (books)';
  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE books');
  }
}

class _$002AddBookPrice extends MigrationBase {
  _$002AddBookPrice();
  @override
  String get id => '002';
  @override
  String get name => 'Add book price';
  @override
  void up(MigrationExecutor exec) {
    exec('ALTER TABLE books ADD COLUMN price INTEGER');
  }

  @override
  void down(MigrationExecutor exec) {
    // SQLite doesn't support DROP COLUMN, so we use the
    // 12-step dance. For test purposes, drop + recreate.
    exec('DROP TABLE books');
    exec('CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)');
  }
}

/// A context that uses only the sync SQLite provider.
class _TestContext extends DbContext {
  _TestContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  final List<MigrationBase> _migrations = <MigrationBase>[];
  @override
  List<MigrationBase> get migrations => _migrations;

  // The DbSet machinery is required by the abstract
  // base class but unused in these tests.
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}

/// A context that uses the async SQLite provider.
class _TestContextAsync extends DbContext {
  _TestContextAsync(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  final List<MigrationBase> _migrations = <MigrationBase>[];
  @override
  List<MigrationBase> get migrations => _migrations;

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}

/// A context with NO async provider (for the error test).
class _TestContextSync extends DbContext {
  _TestContextSync();
  @override
  AsyncQueryProvider? get asyncProvider => null;

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}
