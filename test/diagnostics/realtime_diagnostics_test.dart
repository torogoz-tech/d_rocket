import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../realtime/fake_reconnecting_websocket.dart';

void main() {
  final DrocketDiagnostics diagnostics = DrocketDiagnostics.instance;

  setUp(() {
    diagnostics.clear();
    diagnostics.configure(
      enabled: true,
      publishToVmService: false,
      includeSensitiveData: false,
    );
  });

  tearDown(() {
    diagnostics.clear();
    diagnostics.configure(enabled: false, publishToVmService: true);
  });

  test('records correlated WebSocket lifecycle diagnostics', () async {
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

    await reconnector.start();
    await clients.first.disconnect();
    await Future<void>.delayed(const Duration(milliseconds: 5));

    final List<DiagnosticEvent> events = diagnostics.snapshot
        .where((DiagnosticEvent event) => event.operation == 'websocket.state')
        .toList();
    final DiagnosticEvent retrying = events.singleWhere(
      (DiagnosticEvent event) => event.metadata['state'] == 'retrying',
    );

    expect(retrying.correlationId, isNotNull);
    expect(retrying.metadata['attempt'], 1);
    expect(retrying.metadata['url'], 'wss://example.test');
    await reconnector.dispose();
  });

  test('exposes the last failure and optional close details', () async {
    final WebSocketReconnector reconnector = WebSocketReconnector(
      factory: () => _FailingWebSocket(),
      url: Uri.parse('wss://example.test'),
      maxAttempts: 1,
    );

    await expectLater(reconnector.start(), throwsStateError);

    expect(reconnector.lastError, isA<StateError>());
    expect(reconnector.lastCloseCode, 4003);
    expect(reconnector.lastCloseReason, 'forbidden');
    final DiagnosticEvent failed = diagnostics.snapshot.lastWhere(
      (DiagnosticEvent event) => event.metadata['state'] == 'failed',
    );
    expect(failed.error, 'StateError');
    expect(failed.error, isNot(contains('super-secret')));
    await reconnector.dispose();
  });
}

class _FailingWebSocket implements WebSocketConnection {
  int? get statusCode => 403;

  int? get closeCode => 4003;

  String? get closeReason => 'forbidden';

  @override
  Stream<WebSocketMessage> get messages =>
      const Stream<WebSocketMessage>.empty();

  @override
  bool get isConnected => false;

  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    throw StateError('Bearer super-secret');
  }

  @override
  Future<void> send(WebSocketMessage message) async {}

  @override
  Future<void> close({int? code, String? reason}) async {}
}
