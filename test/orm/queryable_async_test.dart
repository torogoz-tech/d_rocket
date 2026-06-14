// Tests for the async terminal methods on
// `Queryable<T>`: `toListAsync_`, `countAsync_`,
// `toListWithJoinsAsync_`. The async path goes through the
// `AsyncQueryProvider` interface.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
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

  group('Fase 5.0+3 — Queryable.*Async requires AsyncQueryProvider', () {
    test('toListAsync_ throws when no async provider is attached', () async {
      // Build a queryable from a DbSet that has NO
      // async provider attached.
      final dbSetNoAsync = DbSet<_Book>(
        metaAccessor: () => _bookMeta,
        tracker: ChangeTracker(),
        execute: (_, __) => 1,
        select: (_, __) => const <Object?>[],
        lastInsertRowId: () => 0,
      );
      // Build a queryable manually (without going through
      // the DbSet's helpers).
      final q = Queryable<_Book>(
        provider: provider,
        table: 'books',
        reader: (row) =>
            _Book(id: row['id']! as int, title: row['title']! as String),
        meta: _bookMeta,
      );
      // Sanity: the queryable is NOT async.
      await expectLater(
        () async => q.toListAsync_(),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('requires an AsyncQueryProvider'),
        )),
      );
      // Reference dbSetNoAsync to silence the analyzer.
      expect(dbSetNoAsync, isNotNull);
    });

    test('countAsync_ throws when no async provider is attached', () async {
      final q = Queryable<_Book>(
        provider: provider,
        table: 'books',
        reader: (_) => _Book(id: 0, title: ''),
        meta: _bookMeta,
      );
      await expectLater(
        () async => q.countAsync_(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Fase 5.0+3 — Queryable.*Async with async provider wired', () {
    test('toListAsync_ returns the matching rows', () async {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.books.add(_Book(id: 0, title: 'Foundation'));
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      ctx.saveChanges();

      final q = ctx.books.asQueryable();
      final List<_Book> all = await q.toListAsync_();
      expect(all, hasLength(3));
      final Set<String> titles = all.map((_Book b) => b.title).toSet();
      expect(titles, <String>{'Dune', 'Foundation', 'Hyperion'});
    });

    test('Chained LINQ with toListAsync_ (where_ + orderBy_)', () async {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.books.add(_Book(id: 0, title: 'Foundation'));
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      ctx.saveChanges();

      final q = ctx.books
          .asQueryable()
          .where_(Expr.lambda(
            <Expr>[Expr.param('u')],
            Expr.binary(
                '>', Expr.member(Expr.param('u'), 'id'), Expr.const_(1)),
          ))
          .orderBy_(Expr.lambda(
            <Expr>[Expr.param('u')],
            Expr.member(Expr.param('u'), 'id'),
          ));
      final List<_Book> filtered = await q.toListAsync_();
      // The first book (id=1) is filtered out by
      // `id > 1`. So we expect 2 books.
      expect(filtered, hasLength(2));
      final Set<String> titles = filtered.map((_Book b) => b.title).toSet();
      expect(titles, <String>{'Foundation', 'Hyperion'});
    });

    test('countAsync_ returns the row count', () async {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.books.add(_Book(id: 0, title: 'Foundation'));
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      ctx.saveChanges();

      final q = ctx.books.asQueryable();
      expect(await q.countAsync_(), 3);
    });

    test('countAsync_ with where_ filters correctly', () async {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.books.add(_Book(id: 0, title: 'Foundation'));
      ctx.books.add(_Book(id: 0, title: 'Hyperion'));
      ctx.saveChanges();

      final q = ctx.books.asQueryable().where_(Expr.lambda(
            <Expr>[Expr.param('u')],
            Expr.binary(
                '>', Expr.member(Expr.param('u'), 'id'), Expr.const_(1)),
          ));
      expect(await q.countAsync_(), 2);
    });

    test('countAsync_ returns 0 for an empty table', () async {
      final q = ctx.books.asQueryable();
      expect(await q.countAsync_(), 0);
    });

    test('take_ + skip_ + toListAsync_ (pagination)', () async {
      for (int i = 0; i < 10; i++) {
        ctx.books.add(_Book(id: 0, title: 'Book $i'));
      }
      ctx.saveChanges();

      final q = ctx.books
          .asQueryable()
          .orderBy_(Expr.lambda(
            <Expr>[Expr.param('u')],
            Expr.member(Expr.param('u'), 'id'),
          ))
          .skip_(3)
          .take_(4);
      final List<_Book> page = await q.toListAsync_();
      expect(page, hasLength(4));
    });
  });

  group('Fase 5.0+3 — sync API still works (no breaking change)', () {
    test('toList_() still works synchronously', () {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.saveChanges();

      final List<_Book> all = ctx.books.asQueryable().toList_();
      expect(all, hasLength(1));
    });

    test('count_() still works synchronously', () {
      ctx.books.add(_Book(id: 0, title: 'Dune'));
      ctx.saveChanges();

      expect(ctx.books.asQueryable().count_(), 1);
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
    final DbSet<T> s = DbSet<T>(
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
    s.attach<SqliteQueryProvider>(_provider);
    return s;
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
