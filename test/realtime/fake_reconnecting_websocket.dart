import 'dart:async';

import 'package:d_rocket/d_rocket.dart';

class FakeReconnectingWebSocket implements WebSocketConnection {
  FakeReconnectingWebSocket();

  final StreamController<WebSocketMessage> controller =
      StreamController<WebSocketMessage>.broadcast();
  bool connected = false;

  @override
  Stream<WebSocketMessage> get messages => controller.stream;

  @override
  bool get isConnected => connected;

  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    connected = true;
  }

  @override
  Future<void> send(WebSocketMessage message) async {}

  Future<void> disconnect() async {
    connected = false;
    await controller.close();
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    connected = false;
  }
}
