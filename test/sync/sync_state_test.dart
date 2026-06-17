//: tests for the
// [SyncStateStore] implementations +
// `ctx.bootstrapSync` + auto-persist on
// `ctx.syncAsync`.

import 'dart:io';

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.12 — InMemorySyncStateStore: shape', () {
    test('empty store returns null + 0', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      expect(await store.getClientIdAsync(), isNull);
      expect(await store.getWatermarkAsync(), 0);
    });

    test('set + get round-trips the clientId', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      await store.setClientIdAsync('client-abc');
      expect(await store.getClientIdAsync(), 'client-abc');
    });

    test('set + get round-trips the watermark', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      await store.setWatermarkAsync(42);
      expect(await store.getWatermarkAsync(), 42);
    });

    test('clear() resets everything', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      await store.setClientIdAsync('client-abc');
      await store.setWatermarkAsync(42);
      await store.clearAsync();
      expect(await store.getClientIdAsync(), isNull);
      expect(await store.getWatermarkAsync(), 0);
    });

    test('initial values via constructor', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore(
        initialClientId: 'pre-seeded',
        initialWatermark: 100,
      );
      expect(await store.getClientIdAsync(), 'pre-seeded');
      expect(await store.getWatermarkAsync(), 100);
    });
  });

  group('Fase 5.12 — FileSyncStateStore: file I/O round-trip', () {
    late Directory tempDir;
    late String filePath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('d_rocket_sync_');
      filePath = '${tempDir.path}/sync_state.json';
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('an empty file returns null + 0', () async {
      final FileSyncStateStore store = FileSyncStateStore(filePath);
      expect(await store.getClientIdAsync(), isNull);
      expect(await store.getWatermarkAsync(), 0);
    });

    test('set + get round-trips through a real JSON file', () async {
      final FileSyncStateStore store = FileSyncStateStore(filePath);
      await store.setClientIdAsync('phone-1234');
      await store.setWatermarkAsync(99);
      // Re-open and re-read.
      final FileSyncStateStore store2 = FileSyncStateStore(filePath);
      expect(await store2.getClientIdAsync(), 'phone-1234');
      expect(await store2.getWatermarkAsync(), 99);
    });

    test('clear() deletes the file', () async {
      final FileSyncStateStore store = FileSyncStateStore(filePath);
      await store.setClientIdAsync('phone-1234');
      expect(File(filePath).existsSync(), isTrue);
      await store.clearAsync();
      expect(File(filePath).existsSync(), isFalse);
    });
  });

  group('Fase 5.12 — ctx.bootstrapSync: lifecycle', () {
    test('generates a new clientId if none persisted', () async {
      final _SyncContext ctx = _SyncContext();
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      final String id = await ctx.bootstrapSync(store);
      // The id is non-empty and starts with 'client-'.
      expect(id, startsWith('client-'));
      // The store has the id.
      expect(await store.getClientIdAsync(), id);
      // The context's `clientId` getter reflects it.
      expect(ctx.clientId, id);
    });

    test('reuses a persisted clientId on a second bootstrap', () async {
      final _SyncContext ctx1 = _SyncContext();
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      final String id1 = await ctx1.bootstrapSync(store);
      // Simulate app restart with a fresh context.
      final _SyncContext ctx2 = _SyncContext();
      final String id2 = await ctx2.bootstrapSync(store);
      // The same id is reused.
      expect(id2, id1);
    });

    test('forceNewId: true regenerates the id', () async {
      final _SyncContext ctx1 = _SyncContext();
      final InMemorySyncStateStore store = InMemorySyncStateStore();
      final String id1 = await ctx1.bootstrapSync(store);
      // Force a new id.
      final _SyncContext ctx2 = _SyncContext();
      final String id2 = await ctx2.bootstrapSync(store, forceNewId: true);
      expect(id2, isNot(id1));
    });

    test('loads the persisted watermark', () async {
      final InMemorySyncStateStore store = InMemorySyncStateStore(
        initialWatermark: 42,
      );
      final _SyncContext ctx = _SyncContext();
      await ctx.bootstrapSync(store);
      // The watermark is loaded into the context.
      expect(ctx.syncWatermark, 42);
    });
  });

  group('Fase 5.12 — syncAsync: auto-persist on success', () {
    late _SyncContext ctx;
    late InMemorySyncStateStore store;
    late InMemorySyncProvider sync;
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      provider.execute(
        'CREATE TABLE books ('
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,'
        '  title TEXT NOT NULL)',
      );
      ctx = _SyncContext();
      ctx.attachProvider(provider);
      store = InMemorySyncStateStore();
      sync = InMemorySyncProvider();
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('auto-persists the new watermark on success', () async {
      await ctx.bootstrapSync(store);
      // Inject a change to bump the server's
      // watermark (otherwise an empty pull +
      // empty push leaves the watermark at 0).
      sync.injectChange(
        SyncChange(
          tableName: 'books',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'id': 1, 'title': 'X'},
          version: 1,
        ),
      );
      await ctx.syncAsync(sync, stateStore: store);
      // The watermark is now in the store.
      expect(await store.getWatermarkAsync(), greaterThan(0));
    });

    test('without stateStore, nothing is persisted', () async {
      await ctx.bootstrapSync(store);
      // Sync without stateStore.
      await ctx.syncAsync(sync);
      // The store watermark is still 0.
      expect(await store.getWatermarkAsync(), 0);
    });

    test('syncAsync without a clientId throws', () async {
      // Don't bootstrap — so clientId is null.
      expect(
        () => ctx.syncAsync(sync),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _SyncContext extends DbContext {
  _SyncContext();
  late SqliteQueryProvider _provider;
  void attachProvider(SqliteQueryProvider p) {
    _provider = p;
  }

  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}
