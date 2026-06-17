//: tests for the push-side
// pipeline — `saveChangesAsync` populates the
// pending queue, `syncAsync` pushes it + clears.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.11 — pendingSyncChanges: queue grows on saveChanges', () {
    late SqliteQueryProvider provider;
    late _SyncContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      ctx = _SyncContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('the queue starts empty', () {
      expect(ctx.pendingSyncChanges, isEmpty);
    });

    test('saveChangesAsync appends a SyncChange (Added) to the queue',
        () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      // The queue now has 1 upsert.
      expect(ctx.pendingSyncChanges, hasLength(1));
      final SyncChange c = ctx.pendingSyncChanges.first;
      expect(c.tableName, 'books');
      expect(c.pk, '1');
      expect(c.type, SyncChangeType.upsert);
      expect(c.payload, isNotNull);
      expect(c.payload!['title'], 'Rex');
    });

    test('multiple saves accumulate in the queue', () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      ctx.books.add(Book(id: 2, title: 'Whiskers'));
      await ctx.saveChangesAsync();
      // The queue has 2 upserts.
      expect(ctx.pendingSyncChanges, hasLength(2));
    });
  });

  group('Fase 5.11 — syncAsync: pushes the queue + drains on success', () {
    late SqliteQueryProvider provider;
    late InMemorySyncProvider sync;
    late _SyncContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      sync = InMemorySyncProvider();
      ctx = _SyncContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('syncAsync pushes the pending queue + drains it', () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      // Pre-condition: queue has 1.
      expect(ctx.pendingSyncChanges, hasLength(1));
      // Sync.
      await ctx.syncAsync(sync, clientId: 'client-1');
      // Post-condition: queue is empty.
      expect(ctx.pendingSyncChanges, isEmpty);
      // The server received the push.
      expect(sync.pushLog, hasLength(1));
      expect(sync.pushLog.first.changes, hasLength(1));
      expect(sync.pushLog.first.changes.first.tableName, 'books');
    });

    test('syncAsync advances the watermark on success', () async {
      // Make a change + sync (this should bump
      // the server watermark and advance ours).
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      final int beforeSync = ctx.syncWatermark;
      await ctx.syncAsync(sync, clientId: 'client-1');
      // The watermark advances (server bumped it
      // for our push).
      expect(ctx.syncWatermark, greaterThan(beforeSync));
    });

    test('without any local changes, syncAsync sends an empty envelope',
        () async {
      await ctx.syncAsync(sync, clientId: 'client-1');
      expect(sync.pushLog, hasLength(1));
      expect(sync.pushLog.first.changes, isEmpty);
    });

    test('the pushed changes are visible to other clients (pull side)',
        () async {
      ctx.books.add(Book(id: 1, title: 'Rex'));
      await ctx.saveChangesAsync();
      await ctx.syncAsync(sync, clientId: 'client-A');
      // Client-B pulls and should see the change.
      final SyncEnvelope forB = await sync.syncAsync(
        SyncEnvelope(
          clientId: 'client-B',
          since: 0,
          changes: <SyncChange>[],
        ),
      );
      expect(forB.changes, hasLength(1));
      expect(forB.changes.first.tableName, 'books');
      expect(forB.changes.first.payload!['title'], 'Rex');
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

class _SyncContext extends DbContext {
  _SyncContext(this._provider);
  final SqliteQueryProvider _provider;
  late final _BooksDbSet books = dbSet<Book>(_BooksDbSet._meta) as _BooksDbSet;
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
      fromRow: (Map<String, Object?> row) {
        return Book(
          id: row['id']! as int,
          title: row['title']! as String,
        );
      },
    );
  }
}
