// Web stub for [IOWebSocketClient].
//
// d_rocket targets the full Flutter matrix (iOS,
// Android, web, Windows, macOS, Linux) and the Dart
// VM. On native platforms the WebSocket client is
// backed by `dart:io` (see `io_websocket_client.dart`).
// On the web `dart:io` is not available, so this
// stub is the conditional-import target. Every
// operation throws [UnsupportedError].
//
// To wire a real web transport, drop in
// `package:web_socket_channel` (or any equivalent)
// behind a [WebSocketConnection] adapter and replace
// this stub. The public interface is intentionally
// identical to `IOWebSocketClient` so the call site
// does not need to change.

import 'dart:async';

import 'websocket_connection.dart';
import 'websocket_message.dart';

class IOWebSocketClient implements WebSocketConnection {
  IOWebSocketClient();

  Never _unsupported() => throw UnsupportedError(
        'IOWebSocketClient is not available on the web. '
        'Use a `package:web_socket_channel`-backed '
        '`WebSocketConnection` adapter (see '
        '`lib/src/realtime/web_websocket_client.dart`).',
      );

  @override
  Future<void> connect(
    Uri url, {
    Map<String, String>? headers,
  }) =>
      Future<void>.error(_unsupported());

  @override
  Future<void> send(WebSocketMessage message) async => _unsupported();

  @override
  Future<void> close({int? code, String? reason}) async => _unsupported();

  @override
  Stream<WebSocketMessage> get messages => throw _unsupported();

  @override
  bool get isConnected => false;
}
