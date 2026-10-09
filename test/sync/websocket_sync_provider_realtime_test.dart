import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'fake_websocket_connection.dart';

void main() {
  test('sends a sync envelope and resolves the server response', () async {
    late FakeWebSocketConnection connection;
    connection = FakeWebSocketConnection(
      onText: (String text) async {
        final request = jsonDecode(text) as Map<String, Object?>;
        expect(request['type'], 'sync.request');
        connection.emitJson(<String, Object?>{
          'type': 'sync.response',
          'envelope': <String, Object?>{
            'clientId': 'client',
            'since': 4,
            'changes': const <Object?>[],
          },
        });
      },
    );
    final WebSocketSyncProvider provider = WebSocketSyncProvider(
      url: Uri.parse('wss://example.test/sync'),
      connectionFactory: () => connection,
      pushHandler: (PushedSyncChange _) async {},
    );

    final SyncEnvelope response = await provider.syncAsync(
      const SyncEnvelope(clientId: 'client', since: 0, changes: <SyncChange>[]),
    );

    expect(response.since, 4);
    expect(provider.isConnected, isTrue);
    await provider.close();
  });

  test('maps server push events to pushHandler', () async {
    final FakeWebSocketConnection connection = FakeWebSocketConnection();
    final Completer<PushedSyncChange> pushed = Completer<PushedSyncChange>();
    final WebSocketSyncProvider provider = WebSocketSyncProvider(
      url: Uri.parse('wss://example.test/sync'),
      connectionFactory: () => connection,
      pushHandler: (PushedSyncChange value) async {
        pushed.complete(value);
      },
    );
    await provider.connect();
    connection.emitJson(<String, Object?>{
      'type': 'sync.change',
      'originServerId': 'server-a',
      'change': <String, Object?>{
        'tableName': 'events',
        'pk': '1',
        'type': 'upsert',
        'payload': <String, Object?>{'name': 'created'},
        'version': 7,
      },
    });

    final PushedSyncChange result =
        await pushed.future.timeout(const Duration(seconds: 1));
    expect(result.originServerId, 'server-a');
    expect(result.change.version, 7);
    await provider.close();
  });

  test('requests the current watermark through the connection', () async {
    late FakeWebSocketConnection connection;
    connection = FakeWebSocketConnection(
      onText: (String text) async {
        final request = jsonDecode(text) as Map<String, Object?>;
        expect(request['type'], 'sync.watermark.request');
        connection.emitJson(<String, Object?>{
          'type': 'sync.watermark.response',
          'watermark': 12,
        });
      },
    );
    final WebSocketSyncProvider provider = WebSocketSyncProvider(
      url: Uri.parse('wss://example.test/sync'),
      connectionFactory: () => connection,
      pushHandler: (PushedSyncChange _) async {},
    );

    expect(await provider.currentWatermarkAsync(), 12);
    await provider.close();
  });

  test('passes refreshed auth headers on every connection', () async {
    final FakeWebSocketConnection connection = FakeWebSocketConnection();
    var refreshes = 0;
    final WebSocketSyncProvider provider = WebSocketSyncProvider(
      url: Uri.parse('wss://example.test/sync'),
      connectionFactory: () => connection,
      auth: () async => 'token-${++refreshes}',
      pushHandler: (PushedSyncChange _) async {},
    );

    await provider.connect();
    expect(connection.connectedHeaders, <String, String>{
      'Authorization': 'Bearer token-1',
    });
    await provider.close();
  });
}
