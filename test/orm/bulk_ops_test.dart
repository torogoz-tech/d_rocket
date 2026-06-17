//: tests for `executeUpdateAsync` /
// `executeDeleteAsync` — bulk operations on
// `AsyncQueryProvider`. Mirrors EF Core 7+'s
// `ExecuteUpdateAsync` / `ExecuteDeleteAsync`.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.6 — bulk operations: executeUpdateAsync', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL,'
        '  stock INTEGER NOT NULL DEFAULT 0,'
        '  low_stock INTEGER NOT NULL DEFAULT 0)',
      );
      // Insert 5 rows.
      for (int i = 1; i <= 5; i++) {
        provider.execute(
          'INSERT INTO books (title, stock) VALUES (?, ?)',
          <Object?>['Book $i', i * 10],
        );
      }
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('update: bulk-updates every matching row', () async {
      final int affected = await provider.executeUpdateAsync(
        table: 'books',
        setters: <String, Object?>{'low_stock': 1},
        where: 'stock < ?',
        whereBinds: <Object?>[30],
      );
      // Books with stock 10, 20 (< 30) → 2 affected.
      expect(affected, 2);
      // The 2 rows now have low_stock = 1.
      final List<Object?> rows = provider.select(
        'SELECT id, low_stock FROM books WHERE low_stock = 1',
      );
      expect(rows, hasLength(2));
    });

    test('update: with no WHERE, every row is affected', () async {
      final int affected = await provider.executeUpdateAsync(
        table: 'books',
        setters: <String, Object?>{'low_stock': 1},
      );
      // 5 rows in total.
      expect(affected, 5);
    });

    test('update: empty setters throws ArgumentError', () async {
      expect(
        () => provider.executeUpdateAsync(
          table: 'books',
          setters: <String, Object?>{},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('update: a no-op UPDATE returns 0 affected', () async {
      // stock >= 1000000 → no row matches.
      final int affected = await provider.executeUpdateAsync(
        table: 'books',
        setters: <String, Object?>{'low_stock': 1},
        where: 'stock > ?',
        whereBinds: <Object?>[1000000],
      );
      expect(affected, 0);
    });
  });

  group('Fase 5.6 — bulk operations: executeDeleteAsync', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL,'
        '  stock INTEGER NOT NULL DEFAULT 0)',
      );
      for (int i = 1; i <= 5; i++) {
        provider.execute(
          'INSERT INTO books (title, stock) VALUES (?, ?)',
          <Object?>['Book $i', i * 10],
        );
      }
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('delete: bulk-deletes every matching row', () async {
      final int affected = await provider.executeDeleteAsync(
        table: 'books',
        where: 'stock < ?',
        whereBinds: <Object?>[30],
      );
      // Books with stock 10, 20 → 2 deleted.
      expect(affected, 2);
      final List<Object?> rows = provider.select(
        'SELECT title FROM books',
      );
      expect(rows, hasLength(3));
    });

    test('delete: with no WHERE, every row is deleted', () async {
      final int affected = await provider.executeDeleteAsync(
        table: 'books',
      );
      expect(affected, 5);
      final List<Object?> rows = provider.select(
        'SELECT title FROM books',
      );
      expect(rows, isEmpty);
    });

    test('delete: a no-op DELETE returns 0 affected', () async {
      final int affected = await provider.executeDeleteAsync(
        table: 'books',
        where: 'stock > ?',
        whereBinds: <Object?>[1000000],
      );
      expect(affected, 0);
    });
  });

  group('Fase 5.6 — bulk operations: end-to-end with UPDATE then SELECT', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL,'
        '  status TEXT NOT NULL DEFAULT \'active\')',
      );
      for (int i = 1; i <= 3; i++) {
        provider.execute(
          'INSERT INTO books (title) VALUES (?)',
          <Object?>['Book $i'],
        );
      }
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('update then query returns the updated values', () async {
      await provider.executeUpdateAsync(
        table: 'books',
        setters: <String, Object?>{'status': 'archived'},
      );
      final List<Object?> rows = provider.select(
        'SELECT status FROM books',
      );
      final List<String> statuses = <String>[
        for (final Object? r in rows)
          (r as Map<String, Object?>)['status']! as String,
      ];
      expect(statuses, hasLength(3));
      expect(statuses.every((String s) => s == 'archived'), isTrue);
    });
  });
}
