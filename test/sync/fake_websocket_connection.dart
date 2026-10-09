import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';

class FakeWebSocketConnection implements WebSocketConnection {
  FakeWebSocketConnection({this.onText});

  final Future<void> Function(String text)? onText;
  final StreamController<WebSocketMessage> _messages =
      StreamController<WebSocketMessage>.broadcast();
  Map<String, String>? connectedHeaders;
  bool _connected = false;

  @override
  Stream<WebSocketMessage> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    connectedHeaders = headers;
    _connected = true;
  }

  @override
  Future<void> send(WebSocketMessage message) async {
    if (!_connected) throw StateError('not connected');
    if (message.type == WebSocketMessageType.text && message.text != null) {
      await onText?.call(message.text!);
    }
  }

  void emitJson(Map<String, Object?> json) {
    _messages.add(WebSocketMessage.text(jsonEncode(json)));
  }

  Future<void> drop() async {
    _connected = false;
    await _messages.close();
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    _connected = false;
    await _messages.close();
  }
}
