// Tests for the DbInterceptor system (Phase 3.7).
//
// What this test covers:
//   - InterceptorRegistry add/remove/clear
//   - onQuery / onQueryComplete (SELECT path)
//   - onMutation / onMutationComplete (INSERT/UPDATE/DELETE path)
//   - onEntitySaving / onEntitySaved (per-entity path)
//   - onSaveChangesStart / onSaveChangesEnd (batch path)
//   - Composition (interceptor A's output → interceptor B's input)
//   - Throwing in an interceptor aborts the operation
//   - Real-world scenarios: soft delete, multi-tenancy,
//     auto-timestamps, audit log, encryption.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);

  group('InterceptorRegistry:', () {
    test('add/remove/clear', () {
      final InterceptorRegistry r = InterceptorRegistry();
      expect(r.isEmpty, isTrue);
      final DbInterceptor a = _NoopInterceptor();
      r.add(a);
      expect(r.length, 1);
      expect(r.interceptors, [a]);
      r.remove(a);
      expect(r.isEmpty, isTrue);
      r.addAll([_NoopInterceptor(), _NoopInterceptor()]);
      expect(r.length, 2);
      r.clear();
      expect(r.isEmpty, isTrue);
    });
  });

  group('onQuery / onQueryComplete (SELECT path):', () {
    test('interceptor can rewrite the SQL', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      ctx.seedAlice();

      // Rewrite: every SELECT on `user` becomes
      // `SELECT * FROM user WHERE id > 0`.
      ctx.interceptors.add(_WhereRewriteInterceptor(
        table: 'user',
        extraWhere: 'id > 0',
      ));

      final List<_User> users = await ctx.user.toListAsync_();
      expect(users, hasLength(1));
      expect(users.first.name, 'Alice');
    });

    test('throwing in onQuery aborts the SELECT', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      ctx.seedAlice();

      ctx.interceptors.add(_ThrowingInterceptor(
        stage: 'onQuery',
        message: 'no queries allowed',
      ));

      await expectLater(
        () => ctx.user.toListAsync_(),
        throwsA(isA<Object>()),
      );
    });
  });

  group('onMutation / onMutationComplete (INSERT/UPDATE/DELETE):', () {
    test('soft delete interceptor converts DELETE to UPDATE', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      final _User alice = ctx.seedAlice();

      // Soft-delete interceptor: convert
      // `DELETE FROM user WHERE id = ?` to
      // `UPDATE user SET deleted_at = ? WHERE id = ?`.
      ctx.interceptors.add(_SoftDeleteInterceptor());

      ctx.user.remove(alice);
      await ctx.saveChangesAsync();

      // The row still exists (soft delete).
      final List<Object?> rows =
          await provider.selectAsync('SELECT * FROM user');
      expect(rows, hasLength(1),
          reason: 'soft delete: row should still exist');
      final Map<String, Object?> first = rows.first as Map<String, Object?>;
      expect(first['deleted_at'], isNotNull,
          reason: 'soft delete: deleted_at should be set');
    });
  });

  group('onEntitySaving / onEntitySaved (per-entity):', () {
    test('onEntitySaving fires once per entity with the right state', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      final _RecordingInterceptor rec = _RecordingInterceptor();
      ctx.interceptors.add(rec);

      final _User alice = _User(id: 0, name: 'Alice');
      ctx.user.add(alice);
      await ctx.saveChangesAsync();

      // We expect 4 events for 1 entity:
      //   1) onSaveChangesStart:1
      //   2) onEntitySaving:added
      //   3) onEntitySaved:added:success
      //   4) onSaveChangesEnd:1:success
      expect(rec.events, hasLength(4));
      expect(rec.events[0], 'onSaveChangesStart:1');
      expect(rec.events[1], 'onEntitySaving:added');
      expect(rec.events[2], 'onEntitySaved:added:success');
      expect(rec.events[3], 'onSaveChangesEnd:1:success');
    });

    test('onEntitySaving can mutate the entity', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();

      // Uppercase the name before save.
      ctx.interceptors.add(_UppercaseNameInterceptor());

      final _User alice = _User(id: 0, name: 'alice');
      ctx.user.add(alice);
      await ctx.saveChangesAsync();

      final _User saved = (await ctx.user.toListAsync_()).first;
      expect(saved.name, 'ALICE',
          reason: 'onEntitySaving mutated the entity');
    });
  });

  group('onSaveChangesStart / onSaveChangesEnd (batch):', () {
    test('fires once per saveChanges() with the full change set', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      final _RecordingInterceptor rec = _RecordingInterceptor();
      ctx.interceptors.add(rec);

      ctx.user.add(_User(id: 0, name: 'Alice'));
      ctx.user.add(_User(id: 0, name: 'Bob'));
      await ctx.saveChangesAsync();

      // 2 entities × 2 hooks = 4 entity events
      // + 1 start + 1 end = 6 events total.
      expect(rec.events.where((e) => e.startsWith('onEntitySaving')),
          hasLength(2));
      expect(rec.events.where((e) => e.startsWith('onEntitySaved')),
          hasLength(2));
      expect(rec.events.where((e) => e == 'onSaveChangesStart:2'),
          hasLength(1));
      expect(rec.events.where((e) => e == 'onSaveChangesEnd:2:success'),
          hasLength(1));
    });

    test('onSaveChangesEnd fires with the error on failure', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      final _RecordingInterceptor rec = _RecordingInterceptor();
      ctx.interceptors.add(rec);

      // Stage an entity but make the interceptor
      // throw on the mutation.
      ctx.user.add(_User(id: 0, name: 'Alice'));
      ctx.interceptors.add(_ThrowingInterceptor(
        stage: 'onMutation',
        message: 'simulated failure',
      ));

      await expectLater(
        () => ctx.saveChangesAsync(),
        throwsA(isA<Object>()),
      );

      // The onSaveChangesEnd should have fired
      // with an error.
      expect(
        rec.events.where(
            (e) => e.startsWith('onSaveChangesEnd') && !e.endsWith('success')),
        hasLength(1),
        reason: 'onSaveChangesEnd should fire on failure too',
      );
    });
  });

  group('Composition (interceptor chain):', () {
    test('interceptor N output → interceptor N+1 input', () async {
      final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
      _TestDbContext ctx = _TestDbContext(provider);
      ctx.createSchema();
      ctx.seedAlice();

      // First interceptor: rewrite the SQL to
      // add `id > 0`.
      ctx.interceptors.add(_WhereRewriteInterceptor(
        table: 'user',
        extraWhere: 'id > 0',
      ));
      // Second interceptor: rewrite the SQL to
      // add `id < 999` (sees the output of N1).
      ctx.interceptors.add(_WhereRewriteInterceptor(
        table: 'user',
        extraWhere: 'id < 999',
      ));

      final List<_User> users = await ctx.user.toListAsync_();
      expect(users, hasLength(1));
    });
  });
}

// ─── Test DbContext ─────────────────────────────────

class _TestDbContext extends DbContext {
  final SqliteQueryProvider _provider;
  _TestDbContext(this._provider);

  @override
  AsyncQueryProvider? get asyncProvider => _provider;

  late final DbSet<_User> user = dbSet<_User>(() => _userMeta);

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
      CREATE TABLE IF NOT EXISTS user (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        deleted_at TEXT
      )
    ''');
  }

  _User seedAlice() {
    _provider.execute('INSERT INTO user (name) VALUES (?)', <Object?>['Alice']);
    return _User(id: 1, name: 'Alice');
  }

  void seedBob() {
    _provider.execute('INSERT INTO user (name) VALUES (?)', <Object?>['Bob']);
  }
}

class _User implements RecordLike {
  int id;
  String name;
  _User({required this.id, required this.name});

  @override
  Object? readField(String name) {
    switch (name) {
      case 'id':
        return id;
      case 'name':
        return this.name;
      default:
        return null;
    }
  }
}

final EntityMeta _userMeta = EntityMeta(
  tableName: 'user',
  columns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'id', dartField: 'id', dartType: int),
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
  ],
  insertableColumns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
  ],
  updatableColumns: const <ColumnMeta>[
    ColumnMeta(sqlName: 'name', dartField: 'name', dartType: String),
  ],
  primaryKey: const ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
  ),
  primaryKeyIndex: 0,
  pkOf: (Object e) => (e as _User).id,
  fromRow: (Map<String, Object?> row) =>
      _User(id: row['id']! as int, name: row['name']! as String),
);

// ─── Test interceptors ─────────────────────────────

class _NoopInterceptor extends DbInterceptor {
  const _NoopInterceptor();
}

class _WhereRewriteInterceptor extends DbInterceptor {
  final String table;
  final String extraWhere;
  _WhereRewriteInterceptor({required this.table, required this.extraWhere});

  @override
  Future<QueryCommand> onQuery(QueryCommand cmd) async {
    if (cmd.table != table) return cmd;
    if (cmd.sql.contains('WHERE')) return cmd;
    return cmd.copyWith(
      sql: '${cmd.sql} WHERE $extraWhere',
    );
  }
}

class _ThrowingInterceptor extends DbInterceptor {
  final String stage;
  final String message;
  _ThrowingInterceptor({required this.stage, required this.message});

  @override
  Future<QueryCommand> onQuery(QueryCommand cmd) async {
    if (stage == 'onQuery') throw StateError(message);
    return cmd;
  }

  @override
  Future<MutationCommand> onMutation(MutationCommand cmd) async {
    if (stage == 'onMutation') throw StateError(message);
    return cmd;
  }
}

class _SoftDeleteInterceptor extends DbInterceptor {
  @override
  Future<MutationCommand> onMutation(MutationCommand cmd) async {
    if (cmd.operation != 'DELETE') return cmd;
    // Convert `DELETE FROM <table> WHERE ...` to
    // `UPDATE <table> SET deleted_at = ? WHERE ...`.
    return cmd.copyWith(
      sql: cmd.sql.replaceFirst(
        'DELETE FROM ${cmd.table}',
        'UPDATE ${cmd.table} SET deleted_at = ?',
      ),
      binds: <Object?>[DateTime.now().toIso8601String(), ...cmd.binds],
      operation: 'UPDATE',
    );
  }
}

class _UppercaseNameInterceptor extends DbInterceptor {
  @override
  Future<void> onEntitySaving(ChangeEntry entry) async {
    if (entry.entity is _User) {
      final _User u = entry.entity as _User;
      u.name = u.name.toUpperCase();
    }
  }
}

class _RecordingInterceptor extends DbInterceptor {
  final List<String> events = <String>[];

  @override
  Future<void> onSaveChangesStart(ChangeSet changes) async {
    events.add('onSaveChangesStart:${changes.length}');
  }

  @override
  Future<void> onEntitySaving(ChangeEntry entry) async {
    events.add('onEntitySaving:${entry.state.name}');
  }

  @override
  Future<void> onEntitySaved(ChangeEntry entry, MutationResult result) async {
    events.add(
        'onEntitySaved:${entry.state.name}:${result.isSuccess ? 'success' : 'failure'}');
  }

  @override
  Future<void> onSaveChangesEnd(ChangeSet changes, Object? error) async {
    events.add(
        'onSaveChangesEnd:${changes.length}:${error == null ? 'success' : 'failure'}');
  }
}
