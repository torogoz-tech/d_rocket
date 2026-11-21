import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'fake_reconnecting_websocket.dart';

void main() {
  test('refreshes headers before every connection and exposes states',
      () async {
    final List<FakeReconnectingWebSocket> clients =
        <FakeReconnectingWebSocket>[];
    int token = 0;
    final List<WebSocketReconnectorState> states =
        <WebSocketReconnectorState>[];
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () {
        final FakeReconnectingWebSocket client = FakeReconnectingWebSocket();
        clients.add(client);
        return client;
      },
      url: Uri.parse('wss://example.test'),
      headersProvider: () async =>
          <String, String>{'authorization': 'token-${++token}'},
      initialBackoff: Duration.zero,
    );
    final StreamSubscription<WebSocketReconnectorState> stateSubscription =
        reconnector.states.listen(states.add);

    await reconnector.start();
    await reconnector.stop();

    expect(clients.single.lastHeaders,
        <String, String>{'authorization': 'token-1'});
    expect(
        states,
        containsAllInOrder(<WebSocketReconnectorState>[
          WebSocketReconnectorState.connecting,
          WebSocketReconnectorState.connected,
          WebSocketReconnectorState.stopped,
        ]));
    await stateSubscription.cancel();
    await reconnector.dispose();
  });

  test('recovers a 401 with refreshed headers and stops on 403', () async {
    final List<_StatusWebSocket> clients = <_StatusWebSocket>[];
    int token = 0;
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () {
        final _StatusWebSocket client = _StatusWebSocket(
          statusCode: clients.isEmpty ? 401 : null,
        );
        clients.add(client);
        return client;
      },
      url: Uri.parse('wss://example.test'),
      headersProvider: () async =>
          <String, String>{'authorization': 'token-${++token}'},
      onUnauthorized: () async => true,
      initialBackoff: Duration.zero,
      maxAttempts: 2,
    );

    await reconnector.start();
    expect(clients, hasLength(2));
    expect(
        clients.last.lastHeaders, <String, String>{'authorization': 'token-2'});
    await reconnector.stop();

    final _StatusWebSocket forbidden = _StatusWebSocket(statusCode: 403);
    final WebSocketReconnector forbiddenReconnector = WebSocketReconnector(
      factory: () => forbidden,
      url: Uri.parse('wss://example.test'),
      initialBackoff: Duration.zero,
      maxAttempts: 5,
    );
    await expectLater(forbiddenReconnector.start(), throwsA(isA<Object>()));
    expect(forbiddenReconnector.state, WebSocketReconnectorState.failed);
    await forbiddenReconnector.dispose();
  });

  test('reconnects when no inbound activity arrives before timeout', () async {
    final List<FakeReconnectingWebSocket> clients =
        <FakeReconnectingWebSocket>[];
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () {
        final FakeReconnectingWebSocket client = FakeReconnectingWebSocket();
        clients.add(client);
        return client;
      },
      url: Uri.parse('wss://example.test'),
      inactivityTimeout: const Duration(milliseconds: 5),
      initialBackoff: Duration.zero,
    );

    await reconnector.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(clients.length, greaterThanOrEqualTo(2));
    await reconnector.dispose();
  });

  test('can restart and ignores messages from the stopped connection',
      () async {
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
    );
    final List<String> received = <String>[];
    final StreamSubscription<WebSocketMessage> subscription =
        reconnector.messages.listen((WebSocketMessage message) {
      received.add(message.text!);
    });

    await reconnector.start();
    final FakeReconnectingWebSocket first = clients.single;
    await reconnector.stop();
    await reconnector.start();
    final FakeReconnectingWebSocket second = clients.last;
    first.controller.add(WebSocketMessage.text('stale'));
    second.controller.add(WebSocketMessage.text('current'));
    await Future<void>.delayed(Duration.zero);

    expect(received, <String>['current']);
    await subscription.cancel();
    await reconnector.dispose();
  });

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

class _StatusWebSocket implements WebSocketConnection {
  _StatusWebSocket({this.statusCode});

  final int? statusCode;
  final StreamController<WebSocketMessage> _controller =
      StreamController<WebSocketMessage>.broadcast();
  Map<String, String>? lastHeaders;
  bool connected = false;

  @override
  Stream<WebSocketMessage> get messages => _controller.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    lastHeaders = headers;
    if (statusCode != null) {
      throw StateError('HTTP $statusCode');
    }
    connected = true;
  }

  @override
  Future<void> send(WebSocketMessage message) async {}

  @override
  Future<void> close({int? code, String? reason}) async {
    connected = false;
    await _controller.close();
  }
}
