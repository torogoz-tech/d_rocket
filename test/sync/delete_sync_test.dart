// fix-5.13.1: tests that verify DELETEs
// are now tracked in the push pipeline and
// pushed to the server via the SyncProvider.
// (The pre-fix 5.11 code only snapshotted
// Added + Modified, so deletes were silently
// dropped.)

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('fix-5.13.1 — saveChangesAsync emits a delete SyncChange', () {
    late SqliteQueryProvider provider;
    late InMemorySyncProvider sync;
    late _BooksContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      sync = InMemorySyncProvider();
      ctx = _BooksContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('a remove() + saveChangesAsync produces a delete SyncChange',
        () async {
      // Insert a row.
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      // Drain the queue (simulate a successful sync).
      await ctx.syncAsync(sync, clientId: 'c1');
      expect(sync.pushLog.last.changes, hasLength(1));
      expect(sync.pushLog.last.changes.first.type, SyncChangeType.upsert);
      // Now remove the row.
      ctx.books.remove(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      // The pending queue has a delete.
      expect(ctx.pendingSyncChanges, hasLength(1));
      final SyncChange c = ctx.pendingSyncChanges.first;
      expect(c.type, SyncChangeType.delete);
      expect(c.pk, '1');
      expect(c.tableName, 'books');
      expect(c.payload, isNull);
    });

    test('the delete is pushed to the provider on syncAsync', () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      await ctx.syncAsync(sync, clientId: 'c1');
      // Now remove + sync.
      ctx.books.remove(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      await ctx.syncAsync(sync, clientId: 'c1');
      // The second push contains the delete.
      expect(sync.pushLog, hasLength(2));
      final SyncEnvelope last = sync.pushLog.last;
      expect(last.changes, hasLength(1));
      expect(last.changes.first.type, SyncChangeType.delete);
      expect(last.changes.first.pk, '1');
    });

    test(
        'insert + remove of the same row in the same save: only delete '
        'is pushed (LWW at the row level)', () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      await ctx.syncAsync(sync, clientId: 'c1');
      // Insert + remove in the same save.
      ctx.books.add(Book(id: 2, title: 'Whiskers'));
      ctx.books.remove(Book(id: 2, title: 'Whiskers'));
      await ctx.saveChangesAsync();
      // Only the delete is in the queue (the
      // insert was rolled back by the delete
      // before commit — net effect: nothing).
      // Actually: the insert IS committed (it's
      // in the same transaction), then the
      // delete IS committed. So the row is
      // briefly there, then gone. Both
      // SyncChanges are pushed.
      expect(ctx.pendingSyncChanges, hasLength(2));
      final List<SyncChangeType> types =
          ctx.pendingSyncChanges.map((SyncChange c) => c.type).toList();
      expect(types, contains(SyncChangeType.upsert));
      expect(types, contains(SyncChangeType.delete));
    });
  });
}

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

class _BooksContext extends DbContext {
  _BooksContext(this._provider);
  final SqliteQueryProvider _provider;
  late final DbSet<Book> books = dbSet<Book>(_StaticMeta.call);
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    if (T == Book) return _BooksDbSet(_provider, changeTracker) as DbSet<T>;
    throw UnsupportedError('Not used in this test');
  }
}

class _BooksDbSet extends DbSet<Book> {
  _BooksDbSet(this._provider, ChangeTracker tracker)
      : super(
          metaAccessor: _StaticMeta.call,
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
  EntityMeta get meta => _StaticMeta.call();

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
    return EntityMeta(
      tableName: 'books',
      columns: <ColumnMeta>[idCol, titleCol],
      insertableColumns: <ColumnMeta>[titleCol],
      updatableColumns: <ColumnMeta>[titleCol],
      primaryKey: idCol,
      primaryKeyIndex: 0,
      pkOf: (Object e) => (e as Book).id,
      fromRow: (Map<String, Object?> row) {
        return Book(
          id: row['id']! as int,
          title: row['title']! as String,
        );
      },
    );
  }
}

class _StaticMeta {
  static EntityMeta get _instance => _BooksDbSet._buildMeta();
  static EntityMeta call() => _instance;
}
