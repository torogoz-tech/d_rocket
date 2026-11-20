import 'dart:async';

import 'package:d_rocket/d_rocket.dart';

class FakeSseConnection implements SseConnection {
  FakeSseConnection();

  final StreamController<SseEvent> controller =
      StreamController<SseEvent>.broadcast();
  final StreamController<void> activityController =
      StreamController<void>.broadcast();
  Uri? connectedUrl;
  String? connectedLastEventId;
  Map<String, String>? connectedHeaders;
  @override
  int? statusCode;
  bool closed = false;

  @override
  Stream<void> get activity => activityController.stream;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  }) {
    connectedUrl = url;
    connectedLastEventId = lastEventId;
    connectedHeaders = headers;
    return controller.stream;
  }

  void emit(SseEvent event) {
    activityController.add(null);
    controller.add(event);
  }

  void emitHeartbeat() => activityController.add(null);

  Future<void> finish() => controller.close();

  @override
  Future<void> close() async {
    closed = true;
  }
}
