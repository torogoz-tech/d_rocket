import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'fake_reconnecting_websocket.dart';

void main() {
  test('sends configured heartbeats while connected', () async {
    final List<FakeReconnectingWebSocket> clients =
        <FakeReconnectingWebSocket>[];
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () {
        final FakeReconnectingWebSocket client = FakeReconnectingWebSocket();
        clients.add(client);
        return client;
      },
      url: Uri.parse('wss://example.test'),
      initialBackoff: Duration.zero,
      heartbeatInterval: const Duration(milliseconds: 5),
    );

    await reconnector.start();
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(clients.single.sent, isNotEmpty);
    expect(clients.single.sent.first.text, '{"type":"ping"}');
    await reconnector.stop();
  });

  test('reconnects after a mid-session disconnect', () async {
    final List<FakeReconnectingWebSocket> clients =
        <FakeReconnectingWebSocket>[];
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () {
        final FakeReconnectingWebSocket client = FakeReconnectingWebSocket();
        clients.add(client);
        return client;
      },
      url: Uri.parse('wss://example.test'),
      initialBackoff: Duration.zero,
      maxAttempts: 2,
    );
    final List<WebSocketMessage> messages = <WebSocketMessage>[];
    final StreamSubscription<WebSocketMessage> subscription =
        reconnector.messages.listen(messages.add);

    await reconnector.start();
    clients.first.controller.add(WebSocketMessage.text('one'));
    await Future<void>.delayed(Duration.zero);
    await clients.first.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(clients, hasLength(2));
    expect(messages.single.text, 'one');
    await reconnector.stop();
    await subscription.cancel();
  });
}
