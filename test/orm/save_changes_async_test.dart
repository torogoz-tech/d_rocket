// Tests for the async saveChanges path:
// `DbContext.saveChangesAsync`.
//
// What we verify:
// 1. `saveChangesAsync` throws if no `AsyncQueryProvider`
// is attached.
// 2. `saveChangesAsync` INSERTs a new entity and
// back-propagates the auto-PK.
// 3. `saveChangesAsync` UPDATEs a modified entity.
// 4. `saveChangesAsync` DELETEs a removed entity.
// 5. `saveChangesAsync` rolls back the transaction on
// failure (the change tracker entries are preserved).
// 6. Multiple entities in the same batch: inserts +
// updates + deletes — the entire batch is atomic.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  late SqliteQueryProvider provider;
  late _Ctx ctx;

  setUp(() {
    provider = SqliteQueryProvider.inMemory();
    ctx = _Ctx(provider);
    ctx.createSchema();
  });

  tearDown(() async {
    await provider.disposeAsync();
  });

  group('Fase 5.0+2 — saveChangesAsync requires AsyncQueryProvider', () {
    test('throws when no async provider is set on the context', () async {
      // The table was already created in setUp by `ctx`.
      // `_CtxNoAsync` re-uses it (the schema is the same).
      final ctxNoAsync = _CtxNoAsync(provider);
      ctxNoAsync.books.add(_Book(id: 0, title: 'Dune'));
      await expectLater(
        () async => ctxNoAsync.saveChangesAsync(),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('requires an AsyncQueryProvider'),
        )),
      );
    });
  });

  group('Fase 5.0+2 — saveChangesAsync with AsyncQueryProvider', () {
    test('INSERTs a new entity and back-propagates the auto-PK', () async {
      final dune = _Book(id: 0, title: 'Dune');
      ctx.books.add(dune);
      final int affected = await ctx.saveChangesAsync();
      expect(affected, 1, reason: 'one INSERT');
      expect(dune.id, 1, reason: 'PK is back-propagated');

      // The book is now in the DB.
      final List<Map<String, Object?>> rows = provider.selectWithBinds(
        'SELECT id, title FROM books WHERE id = ?',
        [1],
      );
      expect(rows, hasLength(1));
      expect(rows.first['title'], 'Dune');
    });

    test('INSERTs multiple entities in a single transaction', () async {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.books.add(_Book(id: 0, title: 'Foundation'));
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      final int affected = await ctx.saveChangesAsync();
      expect(affected, 3, reason: 'three INSERTs in one batch');

      // All 3 books are in the DB with consecutive PKs.
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id, title FROM books ORDER BY id',
      );
      expect(rows, hasLength(3));
      expect(
        rows.map((Map<String, Object?> r) => r['title']),
        <Object?>['Dune', 'Foundation', 'Hyperion'],
      );
    });

    test('UPDATEs a modified entity', () async {
      final dune = _Book(id: 0, title: 'Dune');
      ctx.books.add(dune);
      await ctx.saveChangesAsync();
      expect(dune.id, 1);

      // Re-read, modify, save.
      final _Book? loaded = await ctx.books.findByIdAsync(1);
      expect(loaded, isNotNull);
      loaded!.title = 'Dune (Revised Edition)';
      ctx.books.markModified(loaded);
      await ctx.saveChangesAsync();

      // The DB has the new title.
      final List<Map<String, Object?>> rows = provider.selectWithBinds(
        'SELECT title FROM books WHERE id = ?',
        [1],
      );
      expect(rows.first['title'], 'Dune (Revised Edition)');
    });

    test('DELETEs a removed entity', () async {
      final dune = _Book(id: 0, title: 'Dune');
      ctx.books.add(dune);
      await ctx.saveChangesAsync();
      expect(dune.id, 1);

      ctx.books.remove(dune);
      await ctx.saveChangesAsync();

      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id FROM books',
      );
      expect(rows, isEmpty);
    });

    test('Mixed batch: INSERT + UPDATE + DELETE in one transaction', () async {
      // 1. Insert two books.
      final dune = _Book(id: 0, title: 'Dune');
      final foundation = _Book(id: 0, title: 'Foundation');
      ctx.books.add(dune);
      ctx.books.add(foundation);
      await ctx.saveChangesAsync();
      expect(dune.id, 1);
      expect(foundation.id, 2);

      // 2. Mixed batch: update dune, add a new one, delete foundation.
      dune.title = 'Dune (2nd ed.)';
      ctx.books.markModified(dune);
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      ctx.books.remove(foundation);
      final int affected = await ctx.saveChangesAsync();
      expect(affected, 3, reason: '1 UPDATE + 1 INSERT + 1 DELETE');

      // Final state: dune updated, hyperion inserted, foundation gone.
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id, title FROM books ORDER BY id',
      );
      expect(rows, hasLength(2));
      expect(
        rows.map((Map<String, Object?> r) =>
            <String, Object?>{'id': r['id'], 'title': r['title']}),
        <Map<String, Object?>>[
          <String, Object?>{'id': 1, 'title': 'Dune (2nd ed.)'},
          <String, Object?>{'id': 3, 'title': 'Hyperion'},
        ],
      );
    });

    test('Rolls back the transaction on INSERT failure (UNIQUE violation)',
        () async {
      //: schema with a UNIQUE column.
      provider.execute('DROP TABLE IF EXISTS books');
      provider.execute('''
        CREATE TABLE books (
          id    INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL UNIQUE
        )
      ''');
      // Pre-insert a book with a given title.
      provider.execute(
        'INSERT INTO books (title) VALUES (?)',
        <Object?>['Existing'],
      );
      // Now try to insert through the context with the
      // SAME title — UNIQUE constraint will throw.
      final collision = _Book(id: 0, title: 'Existing');
      ctx.books.add(collision);
      await expectLater(
        () async => ctx.saveChangesAsync(),
        throwsA(isA<DatabaseException>()),
      );
      // The DB has exactly 1 row (the original).
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT id, title FROM books',
      );
      expect(rows, hasLength(1));
      expect(rows.first['title'], 'Existing');

      // The change tracker still has the failed entry
      // (so the user can fix and re-save).
      expect(collision.id, 0, reason: 'PK was not back-propagated');
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

class _Book implements RecordLike {
  _Book({this.id = 0, required this.title});
  int id;
  String title;

  @override
  Object? readField(String f) => switch (f) {
        'id' => id,
        'title' => title,
        _ => null,
      };

  @override
  String toString() => '_Book(id: $id, title: $title)';
}

final ColumnMeta _idCol = ColumnMeta(
  sqlName: 'id',
  dartField: 'id',
  dartType: int,
  isPrimaryKey: true,
  isAutoIncrement: true,
);

final ColumnMeta _titleCol = ColumnMeta(
  sqlName: 'title',
  dartField: 'title',
  dartType: String,
);

final EntityMeta _bookMeta = EntityMeta(
  tableName: 'books',
  columns: <ColumnMeta>[_idCol, _titleCol],
  insertableColumns: <ColumnMeta>[_titleCol],
  updatableColumns: <ColumnMeta>[_titleCol],
  primaryKey: _idCol,
  primaryKeyIndex: 0,
  pkOf: (Object e) => (e as _Book).id,
  setId: (Object e, Object id) => (e as _Book).id = id as int,
  fromRow: (Map<String, Object?> r) => _Book(
    id: r['id']! as int,
    title: r['title']! as String,
  ),
);

class _Ctx extends DbContext {
  _Ctx(this._provider);
  final SqliteQueryProvider _provider;

  @override
  AsyncQueryProvider? get asyncProvider => _provider;

  late final DbSet<_Book> books = dbSet<_Book>(() => _bookMeta);

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    return DbSet<T>(
      metaAccessor: m,
      tracker: changeTracker,
      execute: (sql, binds) {
        if (binds.isEmpty) {
          _provider.execute(sql);
        } else {
          _provider.execute(sql, binds);
        }
        return 1;
      },
      select: (sql, binds) {
        if (binds.isEmpty) {
          return _provider.select(sql);
        }
        return _provider.selectWithBinds(sql, binds);
      },
      lastInsertRowId: () => _provider.database.lastInsertRowId,
    );
  }

  void createSchema() {
    _provider.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL
      )
    ''');
  }
}

/// No-async context: same as `_Ctx` but without
/// overriding `asyncProvider`. Used to verify that
/// `saveChangesAsync` throws when no async provider is
/// attached.
class _CtxNoAsync extends _Ctx {
  _CtxNoAsync(super.provider);
  @override
  AsyncQueryProvider? get asyncProvider => null;
}
