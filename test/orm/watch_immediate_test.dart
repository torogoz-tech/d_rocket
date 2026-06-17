//: tests for change-tracker-driven
// `watch` — the stream re-emits immediately
// when `saveChangesAsync` fires (instead of
// waiting for the next poll tick).

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.8.1 — DbSet.watch(): change-tracker driven', () {
    late SqliteQueryProvider provider;
    late _BooksDbSet dbSet;
    late _BooksContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      ctx = _BooksContext(provider);
      // Register the DbSet in the context's cache
      // so saveChangesAsync can find it.
      dbSet = ctx.dbSet<Book>(_BooksDbSet._meta) as _BooksDbSet;
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('watch() re-emits immediately on saveChangesAsync', () async {
      // Use a long pollInterval (1 second) so the
      // re-emit can ONLY be triggered by the
      // change-tracker (not by the timer).
      final Stream<List<Book>> stream = dbSet.watch(
        pollInterval: const Duration(seconds: 1),
      );
      // Capture the first 2 emissions.
      final List<int> emissions = <int>[];
      final Future<void> done =
          stream.take(2).toList().then((List<List<Book>> list) {
        for (final List<Book> rows in list) {
          emissions.add(rows.length);
        }
      });
      // Stage an insert and save.
      dbSet.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      // The first emission should be the initial
      // state (0 rows). The second should be
      // IMMEDIATELY after saveChanges (1 row),
      // without waiting for the 1-second poll.
      await done.timeout(const Duration(milliseconds: 500));
      expect(emissions, <int>[0, 1]);
    });

    test('watch() re-emits on every saveChangesAsync call', () async {
      final Stream<List<Book>> stream = dbSet.watch(
        pollInterval: const Duration(seconds: 1),
      );
      final List<int> emissions = <int>[];
      final Future<void> done =
          stream.take(3).toList().then((List<List<Book>> list) {
        for (final List<Book> rows in list) {
          emissions.add(rows.length);
        }
      });
      // 2 saves with a small delay between them
      // (so the watch has time to re-query after
      // the first save before the second save).
      dbSet.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      dbSet.add(Book(id: 2, title: 'Whiskers'));
      await ctx.saveChangesAsync();
      await done.timeout(const Duration(milliseconds: 500));
      // 0 → 1 → 2.
      expect(emissions, <int>[0, 1, 2]);
    });

    test('watch() also re-emits on the periodic poll (background ticker)',
        () async {
      // Use a SHORT pollInterval (50ms) so the
      // periodic ticker fires.
      final Stream<List<Book>> stream = dbSet.watch(
        pollInterval: const Duration(milliseconds: 50),
      );
      // Take 3 emissions.
      final List<int> emissions = <int>[];
      final Future<void> done =
          stream.take(3).toList().then((List<List<Book>> list) {
        for (final List<Book> rows in list) {
          emissions.add(rows.length);
        }
      });
      // No saveChanges — just wait for the polls.
      await done.timeout(const Duration(milliseconds: 300));
      // 0 → 0 → 0 (same row count, but the stream
      // is still re-emitting on the poll).
      expect(emissions, <int>[0, 0, 0]);
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

/// A minimal Book record for the test.
class Book implements RecordLike {
  Book({required this.id, required this.title});
  final int id;
  final String title;
  @override
  Object? readField(String name) {
    switch (name) {
      case 'id':
        return id;
      case 'title':
        return title;
      default:
        throw StateError('Unknown field $name');
    }
  }
}

/// A minimal context that owns the `books` DbSet.
class _BooksContext extends DbContext {
  _BooksContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    if (T == Book) {
      return _BooksDbSet(_provider, changeTracker) as DbSet<T>;
    }
    throw UnsupportedError('Not used in this test');
  }
}

/// A hand-built DbSet`<Book>` for the `books` table.
/// Uses the shared tracker from the context, so
/// `saveChangesAsync` fires events on the same
/// tracker that `watch` subscribes to.
class _BooksDbSet extends DbSet<Book> {
  _BooksDbSet(this._provider, ChangeTracker tracker)
      : super(
          metaAccessor: _meta,
          tracker: tracker,
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
      pkOf: (Object e) => (e as Book).id,
      setId: (Object e, Object? id) {
        // ignore: invalid_use_of_protected_member
      },
      fromRow: (Map<String, Object?> row) {
        return Book(
          id: row['id']! as int,
          title: row['title']! as String,
        );
      },
    );
  }
}
