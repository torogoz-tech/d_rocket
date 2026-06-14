//: tests for the `seed` hook and
// the `initializeDAsync` one-shot helper.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.7 — seed() hook: default', () {
    test('default seed() is a no-op', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      final _NoSeedContext ctx = _NoSeedContext(provider);
      // Default seed returns immediately.
      await expectLater(ctx.seed(), completes);
      await provider.disposeAsync();
    });
  });

  group('Fase 5.7 — seed() hook: user override', () {
    late SqliteQueryProvider provider;
    late _SeedContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      ctx = _SeedContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('user can override seed() to insert initial data', () async {
      await ctx.seed();
      final List<Object?> rows = provider.select(
        'SELECT title FROM books',
      );
      expect(rows, hasLength(2));
      final List<String> titles = <String>[
        for (final Object? r in rows)
          (r as Map<String, Object?>)['title']! as String,
      ];
      expect(titles, containsAll(<String>['Rex', 'Whiskers']));
    });

    test('seed() is idempotent — re-running does not duplicate', () async {
      await ctx.seed();
      await ctx.seed();
      await ctx.seed();
      final List<Object?> rows = provider.select(
        'SELECT COUNT(*) AS c FROM books',
      );
      final int count = (rows.first as Map<String, Object?>)['c']! as int;
      expect(count, 2,
          reason: 'Even after 3 calls, the table has 2 rows (no duplicate).');
    });
  });

  group('Fase 5.7 — initializeDAsync(): end-to-end', () {
    test('runs migrateAsync() + seed() in one call', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      final _InitializeDContext ctx = _InitializeDContext(provider);

      final List<MigrationBase> applied = await ctx.initializeDAsync();
      // The 1 migration was applied.
      expect(applied, hasLength(1));
      // The seed data was inserted.
      final List<Object?> rows = provider.select(
        'SELECT title FROM books',
      );
      expect(rows, hasLength(1));
      expect(
        (rows.first as Map<String, Object?>)['title'],
        'Seeded',
      );
      await provider.disposeAsync();
    });

    test('initializeDAsync() is idempotent — re-running is a no-op', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      final _InitializeDContext ctx = _InitializeDContext(provider);

      // First call: applies 2 migrations + seeds 1 row.
      await ctx.initializeDAsync();
      // Second call: no migrations, no new rows.
      final List<MigrationBase> applied2 = await ctx.initializeDAsync();
      expect(applied2, isEmpty);
      final List<Object?> rows = provider.select(
        'SELECT COUNT(*) AS c FROM books',
      );
      final int count = (rows.first as Map<String, Object?>)['c']! as int;
      expect(count, 1,
          reason: 'Even after 2 calls, the table has exactly 1 row.');
      await provider.disposeAsync();
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

/// A context with the default no-op seed.
class _NoSeedContext extends DbContext {
  _NoSeedContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}

/// A context that overrides seed to insert 2 books.
class _SeedContext extends DbContext {
  _SeedContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }

  @override
  Future<void> seed() async {
    // Idempotency check — only insert if empty.
    final List<Object?> rows = _provider.select(
      'SELECT COUNT(*) AS c FROM books',
    );
    final int count = (rows.first as Map<String, Object?>)['c']! as int;
    if (count > 0) return;
    _provider.execute('INSERT INTO books (title) VALUES (?)', <Object?>['Rex']);
    _provider.execute(
      'INSERT INTO books (title) VALUES (?)',
      <Object?>['Whiskers'],
    );
  }
}

/// A context that has both migrations and a seed.
class _InitializeDContext extends DbContext {
  _InitializeDContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }

  @override
  List<MigrationBase> get migrations => <MigrationBase>[
        _$001InitialSchema(),
      ];

  @override
  Future<void> seed() async {
    final List<Object?> rows = _provider.select(
      'SELECT COUNT(*) AS c FROM books',
    );
    final int count = (rows.first as Map<String, Object?>)['c']! as int;
    if (count > 0) return;
    _provider.execute(
      'INSERT INTO books (title) VALUES (?)',
      <Object?>['Seeded'],
    );
  }
}

class _$001InitialSchema extends MigrationBase {
  _$001InitialSchema();
  @override
  String get id => '001';
  @override
  String get name => 'Initial schema';
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
