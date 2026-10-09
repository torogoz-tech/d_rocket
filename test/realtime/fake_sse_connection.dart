import 'dart:async';

import 'package:d_rocket/d_rocket.dart';

class FakeSseConnection implements SseConnection {
  FakeSseConnection();

  final StreamController<SseEvent> controller =
      StreamController<SseEvent>.broadcast();
  Uri? connectedUrl;
  String? connectedLastEventId;
  bool closed = false;

  @override
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  }) {
    connectedUrl = url;
    connectedLastEventId = lastEventId;
    return controller.stream;
  }

  void emit(SseEvent event) => controller.add(event);

  Future<void> finish() => controller.close();

  @override
  Future<void> close() async {
    closed = true;
  }
}
