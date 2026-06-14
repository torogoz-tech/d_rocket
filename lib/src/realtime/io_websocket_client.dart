import 'dart:async';
import 'dart:io';

import 'websocket_connection.dart';
import 'websocket_message.dart';
import 'websocket_message_type.dart';

/// WebSocket client backed by `dart:io`'s built-in
/// [WebSocket]. Works on the Dart VM (server-side +
/// tests) and Flutter (iOS / Android / desktop).
class IOWebSocketClient implements WebSocketConnection {
  WebSocket? _socket;

  final StreamController<WebSocketMessage> _messages =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final Completer<void> _closed = Completer<void>();

  @override
  Stream<WebSocketMessage> get messages => _messages.stream;

  /// Broadcast [Stream] of errors that occur on the
  /// WebSocket. The message stream is silent on errors —
  /// use this stream to observe them.
  Stream<Object> get errors => _errors.stream;

  /// [Future] that completes when the connection is
  /// closed (either by the server, the user via [close],
  /// or an error).
  Future<void> get closed => _closed.future;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect(
    Uri url, {
    Map<String, String>? headers,
  }) async {
    if (_socket != null) {
      throw StateError(
        'IOWebSocketClient is already connected. Call close() first.',
      );
    }
    final WebSocket socket =
        await WebSocket.connect(url.toString(), headers: headers);
    _socket = socket;
    socket.listen(
      (dynamic data) {
        if (data is String) {
          _messages.add(WebSocketMessage.text(data));
        } else if (data is List<int>) {
          _messages.add(WebSocketMessage.binary(data));
        }
      },
      onError: (Object e, StackTrace st) {
        _errors.add(e);
      },
      onDone: () {
        _socket = null;
        if (!_closed.isCompleted) {
          _closed.complete();
        }
      },
      cancelOnError: false,
    );
  }

  @override
  Future<void> send(WebSocketMessage message) {
    final WebSocket? socket = _socket;
    if (socket == null) {
      throw StateError('IOWebSocketClient is not connected.');
    }
    switch (message.type) {
      case WebSocketMessageType.text:
        socket.add(message.text!);
        break;
      case WebSocketMessageType.binary:
        socket.add(message.binary!);
        break;
    }
    return Future<void>.value();
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    final WebSocket? socket = _socket;
    if (socket == null) return;
    _socket = null;
    await socket.close(code ?? 1000, reason);
    if (!_closed.isCompleted) {
      _closed.complete();
    }
    await _messages.close();
    await _errors.close();
  }
}
