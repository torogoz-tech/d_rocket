//: tests for the sync layer —
// `SyncProvider`, `InMemorySyncProvider`,
// `ctx.syncAsync(...)`, and the LWW conflict
// resolution on remote changes.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.9 — InMemorySyncProvider: shape', () {
    test('currentWatermarkAsync returns 0 for a fresh provider', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      expect(await provider.currentWatermarkAsync(), 0);
    });

    test('syncAsync with an empty queue returns an empty envelope', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      final SyncEnvelope out = await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-1',
          since: 0,
          changes: <SyncChange>[],
        ),
      );
      expect(out.changes, isEmpty);
    });
  });

  group('Fase 5.9 — ctx.syncAsync(): pull + apply', () {
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

    test('syncAsync pulls and applies a remote UPSERT (insert)', () async {
      // Inject a change as if the server pushed it.
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 1, 'title': 'Remote Book'},
          version: 1,
        ),
      );
      final List<SyncChange> applied = await ctx.syncAsync(
        sync,
        clientId: 'client-A',
      );
      expect(applied, hasLength(1));
      final List<Object?> rows = await provider.selectAsync(
        'SELECT id, title FROM books',
      );
      expect(rows, hasLength(1));
      final Map<String, Object?> row = rows.first as Map<String, Object?>;
      expect(row['id'], 1);
      expect(row['title'], 'Remote Book');
    });

    test('syncAsync pulls and applies a remote UPSERT (update)', () async {
      await provider.executeAsync(
        'INSERT INTO books (id, title) VALUES (?, ?)',
        <Object?>[1, 'Local Title'],
      );
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 1, 'title': 'Updated Title'},
          version: 1,
        ),
      );
      await ctx.syncAsync(sync, clientId: 'client-A');
      final List<Object?> rows = await provider.selectAsync(
        'SELECT title FROM books WHERE id = ?',
        <Object?>[1],
      );
      expect(
        (rows.first as Map<String, Object?>)['title'],
        'Updated Title',
      );
    });

    test('syncAsync pulls and applies a remote DELETE', () async {
      await provider.executeAsync(
        'INSERT INTO books (id, title) VALUES (?, ?)',
        <Object?>[1, 'To Delete'],
      );
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.delete,
          payload: null,
          version: 1,
        ),
      );
      await ctx.syncAsync(sync, clientId: 'client-A');
      final List<Object?> rows = await provider.selectAsync(
        'SELECT id FROM books',
      );
      expect(rows, isEmpty);
    });

    test('syncAsync applies multiple remote changes in order', () async {
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 1, 'title': 'A'},
          version: 1,
        ),
      );
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '2',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 2, 'title': 'B'},
          version: 2,
        ),
      );
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.delete,
          payload: null,
          version: 3,
        ),
      );
      final List<SyncChange> applied = await ctx.syncAsync(
        sync,
        clientId: 'client-A',
      );
      expect(applied, hasLength(3));
      final List<Object?> rows = await provider.selectAsync(
        'SELECT id FROM books',
      );
      expect(rows, hasLength(1));
      expect((rows.first as Map<String, Object?>)['id'], 2);
    });

    test('syncAsync with no remote changes is a no-op', () async {
      final List<SyncChange> applied = await ctx.syncAsync(
        sync,
        clientId: 'client-A',
      );
      expect(applied, isEmpty);
    });
  });

  group('Fase 5.9 — multi-client simulation', () {
    test('changes pushed by client-A are visible to client-B', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      // Client-A pushes a change.
      await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-A',
          since: 0,
          changes: <SyncChange>[
            SyncChange(
              tableName: 'books',
              pk: '1',
              type: SyncChangeType.upsert,
              payload: <String, Object?>{'id': 1, 'title': 'From A'},
              version: 1,
            ),
          ],
        ),
      );
      // Client-B syncs — should see the change.
      final SyncEnvelope forB = await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-B',
          since: 0,
          changes: <SyncChange>[],
        ),
      );
      expect(forB.changes, hasLength(1));
      expect(forB.changes.first.pk, '1');
    });

    test('changes pushed by client-A are NOT re-pulled by client-A', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      // Client-A pushes.
      await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-A',
          since: 0,
          changes: <SyncChange>[
            SyncChange(
              tableName: 'books',
              pk: '1',
              type: SyncChangeType.upsert,
              payload: <String, Object?>{'id': 1, 'title': 'From A'},
              version: 1,
            ),
          ],
        ),
      );
      // Client-A syncs again (empty changes).
      final SyncEnvelope forA = await provider.syncAsync(
        SyncEnvelope(
          clientId: 'client-A',
          since: 0,
          changes: <SyncChange>[],
        ),
      );
      // Client-A shouldn't re-pull its own change.
      expect(forA.changes, isEmpty);
    });
  });
}

class _SyncContext extends DbContext {
  _SyncContext(this._provider);
  final SqliteQueryProvider _provider;
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}
