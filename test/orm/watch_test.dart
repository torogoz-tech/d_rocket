//: tests for `DbSet<T>.watch` —
// the reactive query stream that re-emits on
// every `pollInterval` tick.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.8 — DbSet.watch(): shape', () {
    test('the watch method returns a Stream<List<T>>', () {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      final _BooksDbSet dbSet = _BooksDbSet(provider);
      final Stream<List<int>> stream = dbSet.watch(
        pollInterval: const Duration(milliseconds: 50),
      );
      // The runtime type is a `Stream<List<T>>`.
      expect(stream, isA<Stream<List<int>>>());
      // Cancel immediately (don't actually subscribe).
      // ignore: unawaited_futures, avoid_dynamic_calls
      stream.first.then((_) {}).ignore();
      provider.disposeAsync();
    });
  });

  group('Fase 5.8 — DbSet.watch(): behaviour', () {
    late SqliteQueryProvider provider;
    late _BooksDbSet dbSet;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      dbSet = _BooksDbSet(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('watch() emits the initial state on subscription', () async {
      // Insert 2 rows.
      provider
          .execute('INSERT INTO books (title) VALUES (?)', <Object?>['Rex']);
      provider.execute(
        'INSERT INTO books (title) VALUES (?)',
        <Object?>['Whiskers'],
      );
      // Subscribe and get the first emission.
      final List<int> first = await dbSet
          .watch(pollInterval: const Duration(milliseconds: 100))
          .first;
      expect(first, hasLength(2));
    });

    test('watch() re-emits when the underlying data changes', () async {
      // Start with 0 rows.
      final Stream<List<int>> stream = dbSet.watch(
        pollInterval: const Duration(milliseconds: 100),
      );
      // Capture the first 2 emissions.
      final List<int> emissions = <int>[];
      final Future<void> done =
          stream.take(2).toList().then((List<List<int>> list) {
        for (final List<int> rows in list) {
          emissions.add(rows.length);
        }
      });
      // After a brief delay (50ms — well before the
      // first poll at 100ms), insert a row.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      provider
          .execute('INSERT INTO books (title) VALUES (?)', <Object?>['Rex']);
      await done;
      // The first emission was the initial state (0
      // rows). The second was after the INSERT (1
      // row).
      expect(emissions, <int>[0, 1]);
    });

    test('watch() without an async provider throws', () async {
      final _BooksDbSetNoProvider dbSet = _BooksDbSetNoProvider();
      expect(() => dbSet.watch(), throwsA(isA<StateError>()));
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

/// A hand-built DbSet`<int>` for the `books` table.
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
  EntityMeta get meta => _meta();

  static EntityMeta _meta() {
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
    return EntityMeta(
      tableName: 'books',
      columns: <ColumnMeta>[idCol, titleCol],
      insertableColumns: <ColumnMeta>[titleCol],
      updatableColumns: <ColumnMeta>[titleCol],
      primaryKey: idCol,
      primaryKeyIndex: 0,
      pkOf: (Object e) => 0,
      // The watch tests need a fromRow to
      // materialise rows. We return the PK as
      // the entity (the test only counts
      // emissions, not actual entity content).
      fromRow: (Map<String, Object?> row) {
        return row['id']! as int;
      },
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
