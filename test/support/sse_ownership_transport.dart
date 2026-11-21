import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class SseOwnershipTransport extends http.BaseClient {
  SseOwnershipTransport({this.pendingResponse});

  final Completer<http.StreamedResponse>? pendingResponse;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final Completer<http.StreamedResponse>? pending = pendingResponse;
    if (pending != null) return pending.future;
    return Future<http.StreamedResponse>.value(
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('data: ready\n\n')),
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      ),
    );
  }

  @override
  void close() {
    closed = true;
  }
}
