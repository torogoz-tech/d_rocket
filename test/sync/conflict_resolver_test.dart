//: tests for the
// [ConflictResolver] strategy + the per-DbSet
// wiring in the sync pipeline.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.13 — MergeStrategies: building blocks', () {
    test('preferLocalColumns: keeps the local value for listed columns', () {
      final ConflictResolver resolver = MergeStrategies.preferLocalColumns(
        <String>['display_name'],
      );
      final Map<String, Object?> result = resolver(
        <String, Object?>{'id': 1, 'display_name': 'Local', 'role': 'user'},
        <String, Object?>{'display_name': 'Remote', 'role': 'admin'},
      );
      expect(result['display_name'], 'Local');
      expect(result['role'], 'admin');
    });

    test('preferRemoteColumns: takes the remote value for listed columns', () {
      final ConflictResolver resolver = MergeStrategies.preferRemoteColumns(
        <String>['role'],
      );
      final Map<String, Object?> result = resolver(
        <String, Object?>{'id': 1, 'display_name': 'Local', 'role': 'user'},
        <String, Object?>{'display_name': 'Remote', 'role': 'admin'},
      );
      expect(result['display_name'], 'Local');
      expect(result['role'], 'admin');
    });

    test('maxOf: takes the larger numeric value for counter columns', () {
      final ConflictResolver resolver =
          MergeStrategies.maxOf(<String>['count']);
      final Map<String, Object?> result = resolver(
        <String, Object?>{'id': 1, 'count': 5, 'name': 'X'},
        <String, Object?>{'count': 7, 'name': 'Y'},
      );
      expect(result['count'], 7);
      // Non-counter: remote wins by default.
      expect(result['name'], 'Y');
    });

    test('LwwConflictResolver: remote wins (default behaviour)', () {
      final Map<String, Object?> result = LwwConflictResolver.instance(
        <String, Object?>{'id': 1, 'title': 'Local'},
        <String, Object?>{'title': 'Remote'},
      );
      expect(result['title'], 'Remote');
    });
  });

  group('Fase 5.13 — ctx.syncAsync: per-DbSet conflict resolver', () {
    late SqliteQueryProvider provider;
    late InMemorySyncProvider sync;
    late _ResolvingContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE users ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  display_name TEXT NOT NULL,'
        '  role TEXT NOT NULL DEFAULT \'user\')',
      );
      sync = InMemorySyncProvider();
      ctx = _ResolvingContext(provider);
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('without a conflictResolver, LWW applies (remote wins)', () async {
      // Pre-populate the local row.
      await provider.executeAsync(
        'INSERT INTO users (id, display_name, role) VALUES (?, ?, ?)',
        <Object?>[1, 'Local', 'user'],
      );
      // Server-side change (remote).
      sync.injectChange(
        SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{
            'id': 1,
            'display_name': 'Remote',
            'role': 'admin',
          },
          version: 1,
        ),
      );
      await ctx.syncAsync(sync, clientId: 'client-1');
      // LWW: both fields are remote.
      final List<Object?> rows = await provider.selectAsync(
        'SELECT display_name, role FROM users WHERE id = ?',
        <Object?>[1],
      );
      final Map<String, Object?> row = rows.first as Map<String, Object?>;
      expect(row['display_name'], 'Remote');
      expect(row['role'], 'admin');
    });

    test('with a conflictResolver, the merge function wins', () async {
      // Configure the context with a custom
      // resolver for the users table BEFORE the
      // DbSet is registered. We do this by
      // setting `usersMeta` in setUp, but
      // since the test's setUp already set
      // up the meta, we need to recreate the
      // DbSet. The easiest is to mutate
      // `usersMeta` AND call `registerCounters`
      // (which forces a re-create).
      ctx.usersMeta = _buildUsersMetaWith(
        MergeStrategies.preferLocalColumns(<String>['display_name']),
      );
      // Force a fresh DbSet.
      ctx.registerUsers();
      // Pre-populate the local row.
      await provider.executeAsync(
        'INSERT INTO users (id, display_name, role) VALUES (?, ?, ?)',
        <Object?>[1, 'Local', 'user'],
      );
      // Server-side change.
      sync.injectChange(
        SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{
            'id': 1,
            'display_name': 'Remote',
            'role': 'admin',
          },
          version: 1,
        ),
      );
      await ctx.syncAsync(sync, clientId: 'client-1');
      // The merge: local display_name, remote role.
      final List<Object?> rows = await provider.selectAsync(
        'SELECT display_name, role FROM users WHERE id = ?',
        <Object?>[1],
      );
      final Map<String, Object?> row = rows.first as Map<String, Object?>;
      expect(row['display_name'], 'Local');
      expect(row['role'], 'admin');
    });

    test('maxOf: a counter merge takes the larger value', () async {
      // Configure the context with maxOf for
      // `count`.
      provider.execute(
        'CREATE TABLE counters ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  count INTEGER NOT NULL DEFAULT 0)',
      );
      final EntityMeta counterMeta = _buildCounterMeta();
      ctx.countersMeta = counterMeta;
      // Pre-populate.
      await provider.executeAsync(
        'INSERT INTO counters (id, count) VALUES (?, ?)',
        <Object?>[1, 5],
      );
      // Server-side change (larger count).
      sync.injectChange(
        SyncChange(
          tableName: 'counters',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 1, 'count': 7},
          version: 1,
        ),
      );
      // We need to register the counter resolver
      // in the context — but our MVP only
      // supports one resolver at a time. So we
      // use a different approach: switch the
      // users resolver to maxOf for the
      // counters table.
      ctx.usersMeta = _buildUsersMetaWithMax();
      // Actually, the context's _conflictResolverForTable
      // iterates _dbSets.values. We need a DbSet
      // for the counters table. Simpler: we use
      // the existing users setup with a custom
      // resolver that prefers maxOf for the
      // count column. (No, the table is
      // counters, not users.) Just register a
      // counter DbSet on the context.
      ctx.registerCounters();
      // Now sync.
      await ctx.syncAsync(sync, clientId: 'client-1');
      // The merge: max(5, 7) = 7.
      final List<Object?> rows = await provider.selectAsync(
        'SELECT count FROM counters WHERE id = ?',
        <Object?>[1],
      );
      final Map<String, Object?> row = rows.first as Map<String, Object?>;
      expect(row['count'], 7);
    });
  });
}

EntityMeta _buildUsersMetaWith(ConflictResolver resolver) {
  final EntityMeta base = _buildUsersMeta();
  return EntityMeta(
    tableName: base.tableName,
    columns: base.columns,
    insertableColumns: base.insertableColumns,
    updatableColumns: base.updatableColumns,
    primaryKey: base.primaryKey,
    primaryKeyIndex: base.primaryKeyIndex,
    pkOf: base.pkOf,
    fromRow: base.fromRow,
    conflictResolver: resolver,
  );
}

EntityMeta _buildUsersMetaWithMax() {
  final ColumnMeta idCol = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta nameCol = ColumnMeta(
    sqlName: 'display_name',
    dartField: 'displayName',
    dartType: String,
  );
  final ColumnMeta roleCol = ColumnMeta(
    sqlName: 'role',
    dartField: 'role',
    dartType: String,
  );
  return EntityMeta(
    tableName: 'users',
    columns: <ColumnMeta>[idCol, nameCol, roleCol],
    insertableColumns: <ColumnMeta>[nameCol, roleCol],
    updatableColumns: <ColumnMeta>[nameCol, roleCol],
    primaryKey: idCol,
    primaryKeyIndex: 0,
    pkOf: (Object e) => 0,
    conflictResolver: MergeStrategies.maxOf(<String>['count']),
  );
}

EntityMeta _buildCounterMeta() {
  final ColumnMeta idCol = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta countCol = ColumnMeta(
    sqlName: 'count',
    dartField: 'count',
    dartType: int,
  );
  return EntityMeta(
    tableName: 'counters',
    columns: <ColumnMeta>[idCol, countCol],
    insertableColumns: <ColumnMeta>[countCol],
    updatableColumns: <ColumnMeta>[countCol],
    primaryKey: idCol,
    primaryKeyIndex: 0,
    pkOf: (Object e) => 0,
    conflictResolver: MergeStrategies.maxOf(<String>['count']),
  );
}

class _ResolvingContext extends DbContext {
  _ResolvingContext(this._provider);
  final SqliteQueryProvider _provider;
  EntityMeta usersMeta = _buildUsersMeta();
  EntityMeta countersMeta = _buildCounterMeta();

  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    if (T == int) {
      return _UsersDbSet(_provider, changeTracker, m()) as DbSet<T>;
    }
    if (T == String) {
      return _CountersDbSet(_provider, changeTracker, m()) as DbSet<T>;
    }
    throw UnsupportedError('Not used');
  }

  /// Re-register the counters DbSet after its
  /// meta is updated (e.g. with a custom
  /// conflictResolver).
  void registerCounters() {
    // Force a re-create.
    // ignore: unused_local_variable
    final Object _ = dbSet<String>(() => countersMeta);
  }

  /// Re-register the users DbSet.
  void registerUsers() {
    // ignore: unused_local_variable
    final Object _ = dbSet<int>(() => usersMeta);
  }
}

EntityMeta _buildUsersMeta() {
  final ColumnMeta idCol = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta nameCol = ColumnMeta(
    sqlName: 'display_name',
    dartField: 'displayName',
    dartType: String,
  );
  final ColumnMeta roleCol = ColumnMeta(
    sqlName: 'role',
    dartField: 'role',
    dartType: String,
  );
  return EntityMeta(
    tableName: 'users',
    columns: <ColumnMeta>[idCol, nameCol, roleCol],
    insertableColumns: <ColumnMeta>[nameCol, roleCol],
    updatableColumns: <ColumnMeta>[nameCol, roleCol],
    primaryKey: idCol,
    primaryKeyIndex: 0,
    pkOf: (Object e) => 0,
    fromRow: (Map<String, Object?> row) {
      return <String, Object?>{
        'id': row['id'],
        'display_name': row['display_name'],
        'role': row['role'],
      };
    },
  );
}

class _UsersDbSet extends DbSet<int> {
  _UsersDbSet(
    SqliteQueryProvider provider,
    ChangeTracker tracker,
    this._meta,
  )   : _provider = provider,
        super(
          metaAccessor: _StaticMetaFn(_meta).call,
          tracker: tracker,
          execute: (String sql, List<Object?> binds) {
            provider.execute(sql, binds);
            return 0;
          },
          select: (String sql, List<Object?> binds) {
            return provider.selectWithBinds(sql, binds);
          },
          lastInsertRowId: () => 0,
        ) {
    attachAsyncProvider(_provider);
  }
  final SqliteQueryProvider _provider;
  final EntityMeta _meta;
  @override
  EntityMeta get meta => _meta;
}

class _StaticMetaFn {
  _StaticMetaFn(this._meta);
  final EntityMeta _meta;
  EntityMeta call() => _meta;
}

class _CountersDbSet extends DbSet<String> {
  _CountersDbSet(
    SqliteQueryProvider provider,
    ChangeTracker tracker,
    this._meta,
  )   : _provider = provider,
        super(
          metaAccessor: _StaticMetaFn(_meta).call,
          tracker: tracker,
          execute: (String sql, List<Object?> binds) {
            provider.execute(sql, binds);
            return 0;
          },
          select: (String sql, List<Object?> binds) {
            return provider.selectWithBinds(sql, binds);
          },
          lastInsertRowId: () => 0,
        ) {
    attachAsyncProvider(_provider);
  }
  final SqliteQueryProvider _provider;
  final EntityMeta _meta;
  @override
  EntityMeta get meta => _meta;
}
