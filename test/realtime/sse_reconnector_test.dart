import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'fake_sse_connection.dart';

void main() {
  test('reconnects with Last-Event-ID and forwards events', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
      initialBackoff: Duration.zero,
    );
    final List<SseEvent> events = <SseEvent>[];
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen(events.add);

    await reconnector.start();
    connections.first.emit(const SseEvent(data: 'one', id: 'event-1'));
    await Future<void>.delayed(Duration.zero);
    await connections.first.finish();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(connections, hasLength(2));
    expect(connections[1].connectedLastEventId, 'event-1');
    expect(events.single.data, 'one');

    await reconnector.stop();
    await subscription.cancel();
  });

  test('honors the server retry hint', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
      initialBackoff: const Duration(seconds: 10),
      maxAttempts: 1,
    );
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen((_) {});

    await reconnector.start();
    connections.first.emit(
      const SseEvent(data: 'one', retry: Duration(milliseconds: 1)),
    );
    await Future<void>.delayed(Duration.zero);
    await connections.first.finish();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(connections, hasLength(2));
    await reconnector.stop();
    await subscription.cancel();
  });

  test('resolves headers before every connection attempt', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    int tokenVersion = 0;
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      headersProvider: () async {
        tokenVersion++;
        return <String, String>{'Authorization': 'Bearer token-$tokenVersion'};
      },
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
      initialBackoff: Duration.zero,
      maxAttempts: 1,
    );

    await reconnector.start();
    await connections.first.finish();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(connections, hasLength(2));
    expect(connections[0].connectedHeaders?['Authorization'], 'Bearer token-1');
    expect(connections[1].connectedHeaders?['Authorization'], 'Bearer token-2');
    await reconnector.dispose();
  });

  test('manual acknowledgement advances the resume cursor', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
      manualAcknowledge: true,
      initialBackoff: Duration.zero,
      maxAttempts: 1,
    );
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen((_) {});

    await reconnector.start();
    const SseEvent event = SseEvent(data: 'one', id: 'event-1');
    connections.first.emit(event);
    await Future<void>.delayed(Duration.zero);
    expect(reconnector.lastEventId, isNull);
    reconnector.acknowledge(event);
    await connections.first.finish();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(connections[1].connectedLastEventId, 'event-1');
    await reconnector.dispose();
    await subscription.cancel();
  });

  test('stop prevents stale events and start creates a new generation',
      () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final List<SseEvent> received = <SseEvent>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
    );
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen(received.add);

    await reconnector.start();
    final FakeSseConnection first = connections.first;
    await reconnector.stop();
    first.emit(const SseEvent(data: 'stale'));
    await reconnector.start();
    connections.last.emit(const SseEvent(data: 'fresh'));
    await Future<void>.delayed(Duration.zero);

    expect(received.map((SseEvent event) => event.data), <String>['fresh']);
    expect(reconnector.state, SseReconnectorState.connected);
    await reconnector.dispose();
    await subscription.cancel();
  });

  test('403 fails without retrying indefinitely', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connection.statusCode = 403;
        connections.add(connection);
        return connection;
      },
      initialBackoff: Duration.zero,
      maxAttempts: 5,
    );
    final List<Object> errors = <Object>[];
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen((_) {}, onError: errors.add);

    await reconnector.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(connections, hasLength(1));
    expect(reconnector.state, SseReconnectorState.failed);
    expect(errors.single, isA<SseHttpException>());
    await reconnector.dispose();
    await subscription.cancel();
  });

  test('401 can refresh authentication before retrying', () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    int refreshes = 0;
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      headersProvider: () async => <String, String>{
        'Authorization': 'Bearer $refreshes',
      },
      onUnauthorized: () async {
        refreshes++;
        return true;
      },
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connection.statusCode = connections.isEmpty ? 401 : 200;
        connections.add(connection);
        return connection;
      },
      initialBackoff: Duration.zero,
      maxAttempts: 1,
    );

    await reconnector.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(refreshes, 1);
    expect(connections, hasLength(2));
    expect(connections[1].connectedHeaders?['Authorization'], 'Bearer 1');
    expect(reconnector.state, SseReconnectorState.connected);
    await reconnector.dispose();
  });

  test('failed 401 refresh stops without another connection', () async {
    int connections = 0;
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        connections++;
        final FakeSseConnection connection = FakeSseConnection();
        connection.statusCode = 401;
        return connection;
      },
      onUnauthorized: () async => false,
      initialBackoff: Duration.zero,
    );

    await reconnector.start();
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(connections, 1);
    expect(reconnector.state, SseReconnectorState.failed);
    await reconnector.dispose();
  });

  test('inactivity timeout reconnects but heartbeat activity keeps it alive',
      () async {
    final List<FakeSseConnection> connections = <FakeSseConnection>[];
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: () {
        final FakeSseConnection connection = FakeSseConnection();
        connections.add(connection);
        return connection;
      },
      inactivityTimeout: const Duration(milliseconds: 15),
      initialBackoff: Duration.zero,
      maxAttempts: 1,
    );

    await reconnector.start();
    final FakeSseConnection first = connections.first;
    await Future<void>.delayed(const Duration(milliseconds: 8));
    first.emitHeartbeat();
    await Future<void>.delayed(const Duration(milliseconds: 8));
    expect(connections, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 15));

    expect(connections, hasLength(2));
    await reconnector.dispose();
  });

  test('dispose closes the public event stream', () async {
    final SseReconnector reconnector = SseReconnector(
      url: Uri.parse('https://example.test/events'),
      factory: FakeSseConnection.new,
    );
    bool done = false;
    final StreamSubscription<SseEvent> subscription =
        reconnector.events.listen((_) {}, onDone: () => done = true);

    await reconnector.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(done, isTrue);
    await subscription.cancel();
  });
}
