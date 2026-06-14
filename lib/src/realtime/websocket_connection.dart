import 'websocket_message.dart';

/// Abstract contract for a WebSocket connection.
///
/// Implementations:
/// * [IOWebSocketClient] — `dart:io` (Dart VM + Flutter mobile).
/// * `ChannelWebSocketConnection` — `package:web_socket_channel`
/// for the web.
abstract class WebSocketConnection {
  /// Broadcast [Stream] of incoming messages. Multiple
  /// listeners are supported.
  Stream<WebSocketMessage> get messages;

  /// Opens a connection to [url]. The [headers] (optional)
  /// are sent in the `Connection: Upgrade` request (e.g.
  /// for auth).
  Future<void> connect(Uri url, {Map<String, String>? headers});

  /// Sends a [WebSocketMessage]. Throws [StateError] if
  /// not connected.
  Future<void> send(WebSocketMessage message);

  /// Closes the connection with [code] (default 1000 =
  /// normal closure) and optional [reason].
  Future<void> close({int? code, String? reason});

  /// Whether the connection is open.
  bool get isConnected;
}
