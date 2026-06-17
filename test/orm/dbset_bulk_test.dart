//: tests for `DbSet<T>.executeBulkUpdate`
// and `DbSet<T>.executeBulkDelete` — the typed
// LINQ wrapper around the bulk operations.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.6.1 — DbSet.executeBulkUpdate', () {
    late SqliteQueryProvider provider;
    late _BooksDbSet dbSet;

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
      for (int i = 1; i <= 5; i++) {
        provider.execute(
          'INSERT INTO books (title, stock) VALUES (?, ?)',
          <Object?>['Book $i', i * 10],
        );
      }
      dbSet = _BooksDbSet(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('executeBulkUpdate: the table name comes from entityMeta', () async {
      // The user never types the table name —
      // it comes from the entityMeta.
      final int affected = await dbSet.executeBulkUpdate(
        setters: <String, Object?>{'low_stock': 1},
        where: 'stock < ?',
        whereBinds: <Object?>[30],
      );
      expect(affected, 2);
    });

    test(
        'executeBulkUpdate: no WHERE updates every row (uses entityMeta table)',
        () async {
      final int affected = await dbSet.executeBulkUpdate(
        setters: <String, Object?>{'low_stock': 1},
      );
      expect(affected, 5);
    });

    test('executeBulkUpdate: empty setters throws (delegated to provider)',
        () async {
      expect(
        () => dbSet.executeBulkUpdate(
          setters: <String, Object?>{},
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Fase 5.6.1 — DbSet.executeBulkDelete', () {
    late SqliteQueryProvider provider;
    late _BooksDbSet dbSet;

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
      dbSet = _BooksDbSet(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('executeBulkDelete: bulk-deletes via entityMeta table', () async {
      final int affected = await dbSet.executeBulkDelete(
        where: 'stock < ?',
        whereBinds: <Object?>[30],
      );
      expect(affected, 2);
      final List<Object?> rows = provider.select(
        'SELECT title FROM books',
      );
      expect(rows, hasLength(3));
    });

    test('executeBulkDelete: no WHERE deletes every row', () async {
      final int affected = await dbSet.executeBulkDelete();
      expect(affected, 5);
    });
  });

  group('Fase 5.6.1 — DbSet bulk: error cases', () {
    test('executeBulkUpdate without an async provider throws', () async {
      final _BooksDbSetNoProvider dbSet = _BooksDbSetNoProvider();
      expect(
        () => dbSet.executeBulkUpdate(
          setters: <String, Object?>{'low_stock': 1},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('executeBulkDelete without an async provider throws', () async {
      final _BooksDbSetNoProvider dbSet = _BooksDbSetNoProvider();
      expect(
        () => dbSet.executeBulkDelete(),
        throwsA(isA<StateError>()),
      );
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

/// A DbSet`<Book>` with a hand-built entityMeta (so we
/// don't need codegen for this test). The `books`
/// table is created in the setUp.
class _BooksDbSet extends DbSet<int> {
  _BooksDbSet(this._provider)
      : super(
          metaAccessor: _meta,
          tracker: ChangeTracker(),
          execute: (String sql, List<Object?> binds) {
            _provider.execute(sql, binds);
            return 0;
          },
          select: (String sql, List<Object?> binds) {
            return _provider.selectWithBinds(sql, binds);
          },
          lastInsertRowId: () => 0,
        ) {
    attachAsyncProvider(_provider);
  }
  final SqliteQueryProvider _provider;
  @override
  EntityMeta get meta => _booksMeta;

  static final EntityMeta _booksMeta = _buildMeta();

  static EntityMeta _meta() => _booksMeta;

  static EntityMeta _buildMeta() {
    final ColumnMeta idCol = ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
      isAutoIncrement: true,
    );
    final ColumnMeta titleCol = ColumnMeta(
      sqlName: 'title',
      dartField: 'title',
      dartType: String,
    );
    final ColumnMeta stockCol = ColumnMeta(
      sqlName: 'stock',
      dartField: 'stock',
      dartType: int,
    );
    final ColumnMeta lowStockCol = ColumnMeta(
      sqlName: 'low_stock',
      dartField: 'lowStock',
      dartType: int,
    );
    return EntityMeta(
      tableName: 'books',
      columns: <ColumnMeta>[idCol, titleCol, stockCol, lowStockCol],
      insertableColumns: <ColumnMeta>[titleCol, stockCol, lowStockCol],
      updatableColumns: <ColumnMeta>[titleCol, stockCol, lowStockCol],
      primaryKey: idCol,
      primaryKeyIndex: 0,
      pkOf: (Object e) => 0,
    );
  }
}

class _BooksDbSetNoProvider extends DbSet<int> {
  _BooksDbSetNoProvider()
      : super(
          metaAccessor: _dummyMeta,
          tracker: ChangeTracker(),
          execute: (String sql, List<Object?> binds) => 0,
          select: (String sql, List<Object?> binds) => <Object?>[],
          lastInsertRowId: () => 0,
        );
  @override
  EntityMeta get meta => _dummyMeta();

  static EntityMeta _dummyMeta() {
    final ColumnMeta idCol = ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
      isAutoIncrement: true,
    );
    return EntityMeta(
      tableName: 'books',
      columns: <ColumnMeta>[idCol],
      insertableColumns: <ColumnMeta>[],
      updatableColumns: <ColumnMeta>[],
      primaryKey: idCol,
      primaryKeyIndex: 0,
      pkOf: (Object e) => 0,
    );
  }
}
