// SSE (Server-Sent Events) client over plain HTTP.
//
// Wire format:
//
// ```
// event: foo
// id: 42
// retry: 5000
// data: line 1
// data: line 2
// <— blank line: end of event
// ```
//
// Each event has optional `event`, `id`, `retry`
// fields and one or more `data` lines (joined
// with `\n`). The blank line signals "emit this
// event now".
//
// Uses `package:http` + `Client.send` (streaming)
// so it works on the Dart VM, Flutter, and
// (eventually) the web.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_connection.dart';
import 'sse_event.dart';

/// An SSE client backed by `package:http`. The
/// [httpClient] is DI-friendly (default is a fresh
/// `http.Client` per instance). For tests, inject
/// a `MockClient` or a real `http.Client`.
class HttpSseClient implements SseConnection {
  HttpSseClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  // ignore: unused_field
  http.StreamedResponse? _response;
  StreamController<SseEvent>? _controller;

  @override
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  }) {
    final StreamController<SseEvent> controller = StreamController<SseEvent>();
    _controller = controller;

    Future<void>(() async {
      try {
        final Map<String, String> allHeaders = <String, String>{
          'Accept': 'text/event-stream',
          'Cache-Control': 'no-cache',
          ...?headers,
        };
        if (lastEventId != null) {
          allHeaders['Last-Event-ID'] = lastEventId;
        }

        final http.Request request = http.Request('GET', url);
        request.headers.addAll(allHeaders);

        final http.StreamedResponse response = await _httpClient.send(request);
        if (response.statusCode != 200) {
          controller.addError(StateError(
            'SSE connect failed: HTTP ${response.statusCode}',
          ));
          await controller.close();
          return;
        }
        _response = response;

        final Stream<List<int>> byteStream = response.stream;
        final Stream<String> lineStream =
            byteStream.transform(utf8.decoder).transform(const LineSplitter());

        String dataBuf = '';
        String? eventBuf;
        String? idBuf;
        Duration? retryBuf;

        void emit() {
          if (dataBuf.isEmpty && eventBuf == null && idBuf == null) {
            return;
          }
          controller.add(SseEvent(
            data: dataBuf,
            event: eventBuf,
            id: idBuf,
            retry: retryBuf,
          ));
          dataBuf = '';
          eventBuf = null;
          idBuf = null;
          retryBuf = null;
        }

        final StreamSubscription<String> sub = lineStream.listen(
          (String line) {
            if (line.isEmpty) {
              emit();
              return;
            }
            if (line.startsWith(':')) {
              return;
            }
            final int colon = line.indexOf(':');
            final String field;
            final String value;
            if (colon < 0) {
              field = line;
              value = '';
            } else {
              field = line.substring(0, colon);
              value = colon + 1 < line.length && line[colon + 1] == ' '
                  ? line.substring(colon + 2)
                  : line.substring(colon + 1);
            }
            switch (field) {
              case 'data':
                dataBuf = dataBuf.isEmpty ? value : '$dataBuf\n$value';
                break;
              case 'event':
                eventBuf = value;
                break;
              case 'id':
                idBuf = value;
                break;
              case 'retry':
                final int? ms = int.tryParse(value);
                if (ms != null) retryBuf = Duration(milliseconds: ms);
                break;
            }
          },
          onError: (Object e, StackTrace st) {
            controller.addError(e, st);
          },
          onDone: () {
            emit();
            controller.close();
          },
          cancelOnError: false,
        );

        controller.onCancel = () async {
          await sub.cancel();
        };
      } catch (e, st) {
        controller.addError(e, st);
        await controller.close();
      }
    });

    return controller.stream;
  }

  @override
  Future<void> close() async {
    await _controller?.close();
    _controller = null;
    _response = null;
  }
}
