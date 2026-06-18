// Phase 1a — Tests for the 5 LINQ operators
// that were missing or in 1.x-only-sync form
// in 1.x:
//
//   * reverse_        (SQL: flip the existing
//                      ORDER BY ASC/DESC)
//   * defaultIfEmpty_ (in-memory: append default
//                      if source is empty)
//   * toLookup_       (in-memory: group by key)
//   * zip_            (in-memory: combine
//                      element-wise)
//   * sequenceEqual_  (in-memory: equality check)
//
// Three of these (toLookup_, zip_, sequenceEqual_)
// were already there in 1.x as sync terminals; we
// also add async variants (`toLookupAsync_`,
// `zipAsync_`, `sequenceEqualAsync_`) for the 2.0.0
// idiom.
//
// `reverse_` is a SQL operator (flips ORDER BY at
// the DB level — cheaper than materializing +
// reversing in memory). The other 4 are in-memory.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);

  group('Phase 1a.1 — reverse_:', () {
    test('flips ASC to DESC (SQL)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final entry in [
        <Object?>['Alice', 30, 'active'],
        <Object?>['Bob', 17, 'active'],
        <Object?>['Carol', 25, 'inactive'],
        <Object?>['Dave', 45, 'active'],
        <Object?>['Eve', 12, 'active'],
      ]) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          entry,
        );
      }

      // orderBy_(age) + reverse_() = oldest first.
      final oldestFirst = await ctx.users
          .asQueryable()
          .orderBy_(Expr.lambda(
            [Expr.param('u')],
            Expr.member(Expr.param('u'), 'age'),
          ))
          .reverse_()
          .toListAsync_();
      // For debugging:
      expect(oldestFirst.map((u) => u.name).toList(),
          ['Dave', 'Alice', 'Carol', 'Bob', 'Eve'],
          reason: 'reverse_ should flip ASC to DESC');

      // orderByDescending_(age) + reverse_() = ASC.
      final ascendingAge = await ctx.users
          .asQueryable()
          .orderByDescending_(Expr.lambda(
            [Expr.param('u')],
            Expr.member(Expr.param('u'), 'age'),
          ))
          .reverse_()
          .toListAsync_();
      expect(ascendingAge.map((u) => u.name).toList(),
          ['Eve', 'Bob', 'Carol', 'Alice', 'Dave'],
          reason: 'reverse_ should flip DESC to ASC');
    });

    test('throws when there is no orderBy_', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      expect(
        () => ctx.users.asQueryable().reverse_(),
        throwsA(isA<StateError>()),
        reason: 'reverse_ requires a preceding orderBy_',
      );
    });

    test('composes with thenBy_ (multi-key ORDER BY flipped)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final entry in [
        <Object?>['Alice', 30, 'active'],
        <Object?>['Bob', 17, 'active'],
        <Object?>['Carol', 25, 'inactive'],
      ]) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          entry,
        );
      }

      // orderBy_(age) + thenBy_(name) + reverse_()
      // should flip BOTH keys.
      // ASC age then ASC name: [17=Bob, 25=Carol, 30=Alice]
      // reverse_ = DESC age then DESC name: [30=Alice, 25=Carol, 17=Bob]
      final reversed = await ctx.users
          .asQueryable()
          .orderBy_(Expr.lambda(
            [Expr.param('u')],
            Expr.member(Expr.param('u'), 'age'),
          ))
          .thenBy_(Expr.lambda(
            [Expr.param('u')],
            Expr.member(Expr.param('u'), 'name'),
          ))
          .reverse_()
          .toListAsync_();
      expect(reversed.map((u) => u.name).toList(),
          ['Alice', 'Carol', 'Bob'],
          reason: 'reverse_ should flip all ORDER BY keys');
    });
  });

  group('Phase 1a.2 — defaultIfEmpty_:', () {
    test('returns the source when non-empty', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final name in ['Alice', 'Bob']) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          [name, 30, 'active'],
        );
      }
      final users = await ctx.users
          .asQueryable()
          .where_(Expr.lambda(
            [Expr.param('u')],
            Expr.binary(
              '==',
              Expr.member(Expr.param('u'), 'status'),
              Expr.const_('active'),
            ),
          ))
          .defaultIfEmpty_(
              _User(id: 0, name: 'nobody', age: 0, status: 'none'))
          .toListAsync_();
      expect(users, hasLength(2));
      expect(users.map((u) => u.name).toList(), ['Alice', 'Bob']);
    });

    test('returns the default when empty', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      // No rows inserted.
      final users = await ctx.users
          .asQueryable()
          .where_(Expr.lambda(
            [Expr.param('u')],
            Expr.binary(
              '==',
              Expr.member(Expr.param('u'), 'status'),
              Expr.const_('does-not-exist'),
            ),
          ))
          .defaultIfEmpty_(
              _User(id: 0, name: 'default', age: 0, status: 'none'))
          .toListAsync_();
      expect(users, hasLength(1));
      expect(users.first.name, 'default');
    });
  });

  group('Phase 1a.3 — toLookup_ + toLookupAsync_:', () {
    test('groups by key (sync)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final entry in [
        <Object?>['Alice', 30, 'active'],
        <Object?>['Bob', 17, 'inactive'],
        <Object?>['Carol', 25, 'active'],
        <Object?>['Dave', 45, 'active'],
        <Object?>['Eve', 12, 'inactive'],
      ]) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          entry,
        );
      }
      final byStatus = ctx.users.asQueryable().toLookup_<String>(
          keySelector: Expr.lambda(
        [Expr.param('u')],
        Expr.member(Expr.param('u'), 'status'),
      ));
      expect(byStatus['active'].map((u) => u.name).toList(),
          ['Alice', 'Carol', 'Dave']);
      expect(byStatus['inactive'].map((u) => u.name).toList(),
          ['Bob', 'Eve']);
    });

    test('groups by key (async)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final entry in [
        <Object?>['Alice', 30, 'active'],
        <Object?>['Bob', 17, 'inactive'],
        <Object?>['Carol', 25, 'active'],
      ]) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          entry,
        );
      }
      final byStatus = await ctx.users.asQueryable().toLookupAsync_<String>(
          keySelector: Expr.lambda(
        [Expr.param('u')],
        Expr.member(Expr.param('u'), 'status'),
      ));
      expect(byStatus['active'].map((u) => u.name).toList(),
          ['Alice', 'Carol']);
      expect(byStatus['inactive'].map((u) => u.name).toList(),
          ['Bob']);
    });
  });

  group('Phase 1a.4 — zip_ + zipAsync_:', () {
    test('combines element-wise (sync)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final entry in [
        <Object?>['Alice', 30, 'active'],
        <Object?>['Bob', 17, 'inactive'],
        <Object?>['Carol', 25, 'active'],
      ]) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          entry,
        );
      }
      // Use a second filtered queryable as
      // the other side of the zip (zip_ requires
      // a Queryable<T>, not an IQueryable<T>).
      // Two users: Alice and Carol (status='active').
      final activeUsers = ctx.users.asQueryable().where_(Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '==',
          Expr.member(Expr.param('u'), 'status'),
          Expr.const_('active'),
        ),
      ));
      // Zip users with the same users (via take_(2)).
      // Result: 2 pairs of (user, user) — names match.
      final pairs = ctx.users
          .asQueryable()
          .take_(2)
          .zip_<_User>(activeUsers.take_(2));
      expect(pairs, hasLength(2));
      expect(pairs[0].$1.name, 'Alice');
      expect(pairs[0].$2.name, 'Alice');
    });
  });

  group('Phase 1a.5 — sequenceEqual_ + sequenceEqualAsync_:', () {
    test('returns true for equal sequences (async)', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final name in ['Alice', 'Bob']) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          [name, 30, 'active'],
        );
      }
      final active = ctx.users.asQueryable().where_(Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '==',
          Expr.member(Expr.param('u'), 'status'),
          Expr.const_('active'),
        ),
      ));
      // Two different queryable instances, but
      // same SQL — should be equal. We pass
      // an explicit `equals` that compares
      // _User by value (id + name + status).
      final result = await active.sequenceEqualAsync_(
        active,
        equals: (a, b) =>
            a.id == b.id &&
            a.name == b.name &&
            a.status == b.status,
      );
      expect(result, isTrue);
    });

    test('returns false for different-length sequences', () async {
      final ctx = _TestDbContext();
      ctx.setupSchema();
      for (final name in ['Alice', 'Bob', 'Carol']) {
        ctx.provider.execute(
          'INSERT INTO phase1a_users (name, age, status) '
          'VALUES (?, ?, ?)',
          [name, 30, 'active'],
        );
      }
      final active = ctx.users.asQueryable().where_(Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '==',
          Expr.member(Expr.param('u'), 'status'),
          Expr.const_('active'),
        ),
      ));
      final inactive = ctx.users.asQueryable().where_(Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '==',
          Expr.member(Expr.param('u'), 'status'),
          Expr.const_('inactive'),
        ),
      ));
      // 3 active, 0 inactive — not equal.
      final result = await active.sequenceEqualAsync_(
        inactive,
        equals: (a, b) =>
            a.id == b.id &&
            a.name == b.name &&
            a.status == b.status,
      );
      expect(result, isFalse);
    });
  });
}

// ───: test fixtures ─────────────────────────────

class _User implements RecordLike {
  final int id;
  final String name;
  final int age;
  final String status;
  _User({required this.id, required this.name, required this.age, required this.status});

  @override
  Object? readField(String name) {
    switch (name) {
      case 'id':
        return id;
      case 'name':
        return this.name;
      case 'age':
        return age;
      case 'status':
        return status;
      default:
        return null;
    }
  }
}

class _TestDbContext extends DbContext {
  final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
  late final DbSet<_User> users =
      dbSet<_User>(() => _userMeta);

  @override
  AsyncQueryProvider? get asyncProvider => provider;

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    return DbSet<T>(
      metaAccessor: m,
      tracker: changeTracker,
      execute: (String sql, List<Object?> binds) {
        if (binds.isEmpty) {
          provider.execute(sql);
        } else {
          provider.execute(sql, binds);
        }
        return 1;
      },
      select: (String sql, [List<Object?>? binds]) {
        if (binds == null || binds.isEmpty) {
          return provider.select(sql);
        }
        return provider.selectWithBinds(sql, binds);
      },
      lastInsertRowId: () => provider.database.lastInsertRowId,
    );
  }

  void setupSchema() {
    provider.execute('''
      DROP TABLE IF EXISTS phase1a_users;
      CREATE TABLE phase1a_users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        age INT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
  }
}

final EntityMeta _userMeta = EntityMeta(
  tableName: 'phase1a_users',
  columns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'id', dartField: 'id', dartType: int),
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
    ColumnMeta(sqlName: 'age', dartField: 'age', dartType: int),
    ColumnMeta(sqlName: 'status', dartField: 'status', dartType: String),
  ],
  insertableColumns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
    ColumnMeta(sqlName: 'age', dartField: 'age', dartType: int),
    ColumnMeta(sqlName: 'status', dartField: 'status', dartType: String),
  ],
  updatableColumns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
    ColumnMeta(sqlName: 'age', dartField: 'age', dartType: int),
    ColumnMeta(sqlName: 'status', dartField: 'status', dartType: String),
  ],
  primaryKey: const ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
  ),
  primaryKeyIndex: 0,
  pkOf: (Object e) => (e as _User).id,
  fromRow: (Map<String, Object?> row) => _User(
        id: row['id']! as int,
        name: row['name']! as String,
        age: row['age']! as int,
        status: row['status']! as String,
      ),
);
