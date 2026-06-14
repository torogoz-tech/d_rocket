//: tests for the WebSocket client.
// Uses a real `HttpServer.bind` + `WebSocketTransformer`
// to stand up a local WebSocket server (no mocking
// library needed).

import 'dart:async';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 6.1 — WebSocketMessage: shape', () {
    test('a text message has type=text and a text payload', () {
      final WebSocketMessage msg = WebSocketMessage.text('hello');
      expect(msg.type, WebSocketMessageType.text);
      expect(msg.text, 'hello');
      expect(msg.isText, isTrue);
      expect(msg.isBinary, isFalse);
    });

    test('a binary message has type=binary and a bytes payload', () {
      final WebSocketMessage msg = WebSocketMessage.binary(<int>[1, 2, 3]);
      expect(msg.type, WebSocketMessageType.binary);
      expect(msg.binary, <int>[1, 2, 3]);
      expect(msg.isBinary, isTrue);
    });
  });

  group('Fase 6.1 — IOWebSocketClient: real server', () {
    late HttpServer server;
    late Uri serverUri;
    final List<WebSocket> serverSockets = <WebSocket>[];

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      serverUri = Uri.parse('ws://127.0.0.1:${server.port}');
      server.listen((HttpRequest req) async {
        final WebSocket socket = await WebSocketTransformer.upgrade(req);
        serverSockets.add(socket);
        socket.listen(
          (dynamic data) {
            if (data is String) {
              socket.add('echo:$data');
            } else if (data is List<int>) {
              socket.add(<int>[0xff, ...data]);
            }
          },
        );
      });
    });

    tearDown(() async {
      for (final WebSocket s in serverSockets) {
        await s.close();
      }
      serverSockets.clear();
      await server.close(force: true);
    });

    test('connect + send text + receive echo', () async {
      final IOWebSocketClient client = IOWebSocketClient();
      await client.connect(serverUri);
      expect(client.isConnected, isTrue);

      final Completer<String> echo = Completer<String>();
      final StreamSubscription<WebSocketMessage> sub =
          client.messages.listen((WebSocketMessage m) {
        if (m.isText && m.text!.startsWith('echo:')) {
          echo.complete(m.text);
        }
      });
      await client.send(WebSocketMessage.text('hello'));
      final String got = await echo.future.timeout(
        const Duration(seconds: 2),
      );
      expect(got, 'echo:hello');

      await sub.cancel();
      await client.close();
      expect(client.isConnected, isFalse);
    });

    test('binary frames round-trip', () async {
      final IOWebSocketClient client = IOWebSocketClient();
      await client.connect(serverUri);
      final Completer<List<int>> got = Completer<List<int>>();
      client.messages.listen((WebSocketMessage m) {
        if (m.isBinary && m.binary!.first == 0xff) {
          got.complete(m.binary);
        }
      });
      await client.send(WebSocketMessage.binary(<int>[1, 2, 3, 4]));
      final List<int> bytes = await got.future.timeout(
        const Duration(seconds: 2),
      );
      expect(bytes, <int>[0xff, 1, 2, 3, 4]);
      await client.close();
    });

    test('the client receives onDone when the server closes', () async {
      final IOWebSocketClient client = IOWebSocketClient();
      await client.connect(serverUri);
      final WebSocket serverSocket = serverSockets.first;
      await serverSocket.close();
      await client.closed.timeout(const Duration(seconds: 2));
      expect(client.isConnected, isFalse);
    });

    test('send() before connect() throws StateError', () {
      final IOWebSocketClient client = IOWebSocketClient();
      expect(
        () => client.send(WebSocketMessage.text('x')),
        throwsA(isA<StateError>()),
      );
    });

    test('connect() twice throws StateError', () async {
      final IOWebSocketClient client = IOWebSocketClient();
      await client.connect(serverUri);
      expect(
        () => client.connect(serverUri),
        throwsA(isA<StateError>()),
      );
      await client.close();
    });
  });

  group('Fase 6.1 — WebSocketReconnector: lifecycle', () {
    test('start() retries on failure and gives up after maxAttempts', () async {
      int factoryCalls = 0;
      final WebSocketReconnector reconnector = WebSocketReconnector(
        factory: () {
          factoryCalls++;
          return _AlwaysFailingWs();
        },
        url: Uri.parse('ws://127.0.0.1:1'),
        initialBackoff: const Duration(milliseconds: 1),
        maxAttempts: 3,
      );
      await expectLater(reconnector.start(), throwsA(isA<Exception>()));
      expect(factoryCalls, 3);
      await reconnector.stop();
    });
  });
}

class _AlwaysFailingWs implements WebSocketConnection {
  @override
  Stream<WebSocketMessage> get messages =>
      const Stream<WebSocketMessage>.empty();
  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    throw const SocketException('refused');
  }

  @override
  Future<void> send(WebSocketMessage message) async {}
  @override
  Future<void> close({int? code, String? reason}) async {}
  @override
  bool get isConnected => false;
}
