// SYNC.4 — WebSocketSyncProvider + MultiTransportSyncProvider tests

import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('SyncTransport enum:', () {
    test('has 4 transports', () {
      expect(SyncTransport.values.length, 4);
      expect(SyncTransport.values, contains(SyncTransport.polling));
      expect(SyncTransport.values, contains(SyncTransport.webSocket));
      expect(SyncTransport.values, contains(SyncTransport.sse));
      expect(SyncTransport.values, contains(SyncTransport.udp));
    });
  });

  group('MultiTransportSyncProvider:', () {
    test('starts with polling as active transport', () {
      final _FakeProvider polling = _FakeProvider();
      final MultiTransportSyncProvider m = MultiTransportSyncProvider(
        polling: polling,
      );
      expect(m.activeTransport, SyncTransport.polling);
    });

    test('upgrade: WS present → active becomes webSocket', () async {
      final _FakeProvider polling = _FakeProvider();
      final _FakeProvider ws = _FakeProvider();
      final MultiTransportSyncProvider m = MultiTransportSyncProvider(
        polling: polling,
        webSocket: ws,
      );
      await m.connect();
      expect(m.activeTransport, SyncTransport.webSocket);
      await m.disconnect();
    });

    test('fallback: WS missing, SSE present → sse', () async {
      final _FakeProvider polling = _FakeProvider();
      final _FakeProvider sse = _FakeProvider();
      final MultiTransportSyncProvider m = MultiTransportSyncProvider(
        polling: polling,
        sse: sse,
      );
      await m.connect();
      expect(m.activeTransport, SyncTransport.sse);
      await m.disconnect();
    });

    test('transport changes stream emits the new active transport', () async {
      final _FakeProvider polling = _FakeProvider();
      final _FakeProvider ws = _FakeProvider();
      final MultiTransportSyncProvider m = MultiTransportSyncProvider(
        polling: polling,
        webSocket: ws,
      );
      final List<SyncTransport> seen = <SyncTransport>[];
      final StreamSubscription<SyncTransport> sub = m.transportChanges
          .listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      await m.connect();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await sub.cancel();
      await m.disconnect();
      // First event is replay (polling),
      // then live (webSocket after connect).
      expect(
        seen,
        containsAllInOrder(<SyncTransport>[
          SyncTransport.polling,
          SyncTransport.webSocket,
        ]),
      );
    });

    test('syncAsync delegates to the polling transport', () async {
      final _FakeProvider polling = _FakeProvider();
      final _FakeProvider ws = _FakeProvider();
      final MultiTransportSyncProvider m = MultiTransportSyncProvider(
        polling: polling,
        webSocket: ws,
      );
      final SyncEnvelope envelope = SyncEnvelope(
        clientId: 'a',
        since: 0,
        changes: const <SyncChange>[],
      );
      final SyncEnvelope remote = await m.syncAsync(envelope);
      expect(polling.syncAsyncCallCount, 1);
      expect(ws.syncAsyncCallCount, 0);
      expect(remote, isNotNull);
    });
  });

  group('WebSocketSyncProvider:', () {
    test('isConnected starts false', () {
      final WebSocketSyncProvider ws = WebSocketSyncProvider(
        url: Uri.parse('wss://example.com'),
        pushHandler: (PushedSyncChange _) async {},
      );
      expect(ws.isConnected, isFalse);
    });

    test('connect() with no channel factory is a no-op', () async {
      final WebSocketSyncProvider ws = WebSocketSyncProvider(
        url: Uri.parse('wss://example.com'),
        pushHandler: (PushedSyncChange _) async {},
      );
      await ws.connect();
      expect(ws.isConnected, isFalse);
      await ws.close();
    });

    test('pushHandler is invoked when a change is pushed', () async {
      final List<PushedSyncChange> received = <PushedSyncChange>[];
      final Completer<void> done = Completer<void>();
      final WebSocketSyncProvider ws = WebSocketSyncProvider(
        url: Uri.parse('wss://example.com'),
        pushHandler: (PushedSyncChange change) async {
          received.add(change);
          if (!done.isCompleted) done.complete();
        },
      );
      // Manually invoke the handler (the WS
      // transport is stubbed).
      await ws.pushHandler(PushedSyncChange(
        change: SyncChange(
          tableName: 'users',
          pk: '1',
          type: SyncChangeType.upsert,
          payload: <String, Object?>{'x': 1},
          version: 1,
        ),
        receivedAt: DateTime.now(),
      ));
      await done.future.timeout(const Duration(seconds: 1));
      expect(received.length, 1);
      expect(received.first.change.tableName, 'users');
      await ws.close();
    });

    test('currentWatermarkAsync returns 0 (server tracks)', () async {
      final WebSocketSyncProvider ws = WebSocketSyncProvider(
        url: Uri.parse('wss://example.com'),
        pushHandler: (PushedSyncChange _) async {},
      );
      expect(await ws.currentWatermarkAsync(), 0);
      await ws.close();
    });
  });
}

class _FakeProvider implements SyncProvider {
  int syncAsyncCallCount = 0;
  int currentWatermarkCallCount = 0;
  int currentWatermark = 0;

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    syncAsyncCallCount++;
    return SyncEnvelope(
      clientId: envelope.clientId,
      since: currentWatermark,
      changes: const <SyncChange>[],
    );
  }

  @override
  Future<int> currentWatermarkAsync() async {
    currentWatermarkCallCount++;
    return currentWatermark;
  }
}
