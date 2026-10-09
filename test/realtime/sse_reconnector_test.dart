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
}
