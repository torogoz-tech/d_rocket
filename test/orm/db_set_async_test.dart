// Tests for the async I/O read methods on
// `DbSet<T>`: `toListAsync_`, `findByIdAsync`, `firstByAsync`,
// `allByAsync`. These verify the API surface is async
// (returns `Future<...>`) and that the I/O goes through the
// `AsyncQueryProvider` interface (so the same code works
// against any future provider — Postgres in).

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  late SqliteQueryProvider provider;
  late _CustomerDbContext ctx;

  setUp(() {
    provider = SqliteQueryProvider.inMemory();
    ctx = _CustomerDbContext(provider);
    ctx.createSchema();
  });

  tearDown(() async {
    await provider.disposeAsync();
  });

  group('Fase 5.0+1 — DbSet.*Async requires AsyncQueryProvider', () {
    test('toListAsync_ throws when no async provider is set', () {
      // Build a DbSet without attaching the async
      // provider.
      final dbSet = DbSet<_Customer>(
        metaAccessor: () => _customerMeta,
        tracker: ChangeTracker(),
        execute: (_, __) => 1,
        select: (_, __) => const <Object?>[],
        lastInsertRowId: () => 0,
      );
      // Note: NO `attachAsyncProvider(...)` call.
      expect(
        () => dbSet.toListAsync_(),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('requires an AsyncQueryProvider'),
        )),
      );
    });

    test('findByIdAsync throws when no async provider is set', () {
      final dbSet = DbSet<_Customer>(
        metaAccessor: () => _customerMeta,
        tracker: ChangeTracker(),
        execute: (_, __) => 1,
        select: (_, __) => const <Object?>[],
        lastInsertRowId: () => 0,
      );
      expect(
        () => dbSet.findByIdAsync(1),
        throwsA(isA<StateError>()),
      );
    });

    test('firstByAsync throws when no async provider is set', () {
      final dbSet = DbSet<_Customer>(
        metaAccessor: () => _customerMeta,
        tracker: ChangeTracker(),
        execute: (_, __) => 1,
        select: (_, __) => const <Object?>[],
        lastInsertRowId: () => 0,
      );
      expect(
        () => dbSet.firstByAsync(column: 'id', value: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('allByAsync throws when no async provider is set', () {
      final dbSet = DbSet<_Customer>(
        metaAccessor: () => _customerMeta,
        tracker: ChangeTracker(),
        execute: (_, __) => 1,
        select: (_, __) => const <Object?>[],
        lastInsertRowId: () => 0,
      );
      expect(
        () => dbSet.allByAsync(column: 'name', value: 'X'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Fase 5.0+1 — DbSet.*Async with AsyncQueryProvider attached', () {
    test('toListAsync_ returns a Future<List<T>>', () async {
      // Insert via the sync API.
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.customers.add(_Customer(id: 0, name: 'Bob'));
      ctx.saveChanges();

      // Read via the async API.
      final List<_Customer> list = await ctx.customers.toListAsync_();
      expect(list, hasLength(2));
      final Set<String> names = list.map((_Customer c) => c.name).toSet();
      expect(names, <String>{'Alice', 'Bob'});
    });

    test('toListAsync_ returns empty list when the table is empty', () async {
      final List<_Customer> list = await ctx.customers.toListAsync_();
      expect(list, isEmpty);
    });

    test('findByIdAsync returns the matching entity', () async {
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.customers.add(_Customer(id: 0, name: 'Bob'));
      ctx.saveChanges();

      final _Customer? alice = await ctx.customers.findByIdAsync(1);
      expect(alice, isNotNull);
      expect(alice!.name, 'Alice');

      final _Customer? bob = await ctx.customers.findByIdAsync(2);
      expect(bob, isNotNull);
      expect(bob!.name, 'Bob');
    });

    test('findByIdAsync returns null when the id is not found', () async {
      final _Customer? ghost = await ctx.customers.findByIdAsync(999);
      expect(ghost, isNull);
    });

    test('firstByAsync returns the first match', () async {
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.saveChanges();

      final _Customer? alice =
          await ctx.customers.firstByAsync(column: 'name', value: 'Alice');
      expect(alice, isNotNull);
      expect(alice!.name, 'Alice');
    });

    test('firstByAsync throws on unknown column', () async {
      expect(
        () async =>
            ctx.customers.firstByAsync(column: 'no_such_column', value: 'X'),
        throwsA(isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          contains('not declared in the EntityMeta'),
        )),
      );
    });

    test('allByAsync returns every match', () async {
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.customers.add(_Customer(id: 0, name: 'Bob'));
      ctx.saveChanges();

      final List<_Customer> alices =
          await ctx.customers.allByAsync(column: 'name', value: 'Alice');
      expect(alices, hasLength(2));
      for (final _Customer a in alices) {
        expect(a.name, 'Alice');
      }
    });

    test('attachAsyncProvider is idempotent', () {
      // Calling it twice should not throw.
      ctx.customers
        ..attachAsyncProvider(provider)
        ..attachAsyncProvider(provider);
      // No assertion — the test passes if it doesn't throw.
    });
  });

  group('Fase 5.0+1 — sync API still works (no breaking change)', () {
    test('toList() still works synchronously', () {
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.saveChanges();

      final List<_Customer> list = ctx.customers.toList();
      expect(list, hasLength(1));
    });

    test('findById() still works synchronously', () {
      ctx.customers.add(_Customer(id: 0, name: 'Alice'));
      ctx.saveChanges();

      final _Customer? alice = ctx.customers.findById(1);
      expect(alice, isNotNull);
      expect(alice!.name, 'Alice');
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

class _Customer implements RecordLike {
  _Customer({this.id = 0, required this.name});
  int id;
  String name;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'name' => name,
        _ => null,
      };

  @override
  String toString() => '_Customer(id: $id, name: $name)';
}

final ColumnMeta _idMeta = ColumnMeta(
  sqlName: 'id',
  dartField: 'id',
  dartType: int,
  isPrimaryKey: true,
  isAutoIncrement: true,
);

final ColumnMeta _nameMeta = ColumnMeta(
  sqlName: 'name',
  dartField: 'name',
  dartType: String,
);

final List<ColumnMeta> _cols = <ColumnMeta>[_idMeta, _nameMeta];
final List<ColumnMeta> _insertable = <ColumnMeta>[_nameMeta];
final List<ColumnMeta> _updatable = <ColumnMeta>[_nameMeta];

final EntityMeta _customerMeta = EntityMeta(
  tableName: 'customers',
  columns: _cols,
  insertableColumns: _insertable,
  updatableColumns: _updatable,
  primaryKey: _idMeta,
  primaryKeyIndex: 0,
  pkOf: (Object e) => (e as _Customer).id,
  setId: (Object e, Object id) => (e as _Customer).id = id as int,
  fromRow: (Map<String, Object?> r) => _Customer(
    id: r['id']! as int,
    name: r['name']! as String,
  ),
);

class _CustomerDbContext extends DbContext {
  _CustomerDbContext(this._provider);
  final SqliteQueryProvider _provider;

  late final DbSet<_Customer> customers = dbSet<_Customer>(
    () => _customerMeta,
  )..attachAsyncProvider(_provider);

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    return DbSet<T>(
      metaAccessor: m,
      tracker: changeTracker,
      execute: (String sql, List<Object?> binds) {
        if (binds.isEmpty) {
          _provider.execute(sql);
        } else {
          _provider.execute(sql, binds);
        }
        return 1;
      },
      select: (String sql, [List<Object?>? binds]) {
        if (binds == null || binds.isEmpty) {
          return _provider.select(sql);
        }
        return _provider.selectWithBinds(sql, binds);
      },
      lastInsertRowId: () => _provider.database.lastInsertRowId,
    );
  }

  void createSchema() {
    _provider.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
  }
}
