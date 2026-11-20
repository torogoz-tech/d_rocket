import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_connection.dart';
import 'sse_event.dart';
import 'sse_http_exception.dart';

/// An SSE client backed by `package:http`.
class HttpSseClient implements SseConnection {
  HttpSseClient({http.Client? httpClient})
      : _httpClient = httpClient,
        _ownsHttpClient = httpClient == null;

  http.Client? _httpClient;
  final bool _ownsHttpClient;
  StreamController<SseEvent>? _controller;
  StreamController<void>? _activityController;
  StreamSubscription<String>? _lineSubscription;
  Completer<void>? _readyCompleter;
  int? _statusCode;
  bool _closed = false;

  @override
  Future<void> get ready => _readyCompleter?.future ?? Future<void>.value();

  @override
  int? get statusCode => _statusCode;

  @override
  Stream<void> get activity =>
      _activityController?.stream ?? const Stream<void>.empty();

  @override
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  }) {
    _closed = false;
    _statusCode = null;
    final StreamController<SseEvent> controller = StreamController<SseEvent>();
    final StreamController<void> activityController =
        StreamController<void>.broadcast();
    _controller = controller;
    _activityController = activityController;
    _readyCompleter = Completer<void>();
    _httpClient ??= http.Client();

    unawaited(_open(
      url,
      headers,
      lastEventId,
      controller,
      activityController,
    ));
    return controller.stream;
  }

  Future<void> _open(
    Uri url,
    Map<String, String>? headers,
    String? lastEventId,
    StreamController<SseEvent> controller,
    StreamController<void> activityController,
  ) async {
    try {
      final Map<String, String> allHeaders = <String, String>{
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?headers,
      };
      if (lastEventId != null) allHeaders['Last-Event-ID'] = lastEventId;

      final http.Request request = http.Request('GET', url)
        ..headers.addAll(allHeaders);
      final http.StreamedResponse response = await _httpClient!.send(request);
      if (_closed || !identical(_controller, controller)) return;
      _statusCode = response.statusCode;
      _readyCompleter?.complete();
      if (response.statusCode != 200) {
        controller.addError(SseHttpException(response.statusCode));
        await controller.close();
        return;
      }

      final Stream<String> lineStream = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      String dataBuf = '';
      String? eventBuf;
      String? idBuf;
      Duration? retryBuf;

      void emit() {
        if (dataBuf.isEmpty && eventBuf == null && idBuf == null) return;
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

      _lineSubscription = lineStream.listen(
        (String line) {
          if (_closed) return;
          activityController.add(null);
          if (line.isEmpty) {
            emit();
            return;
          }
          if (line.startsWith(':')) return;
          final int colon = line.indexOf(':');
          final String field = colon < 0 ? line : line.substring(0, colon);
          final String value = colon < 0
              ? ''
              : colon + 1 < line.length && line[colon + 1] == ' '
                  ? line.substring(colon + 2)
                  : line.substring(colon + 1);
          switch (field) {
            case 'data':
              dataBuf = dataBuf.isEmpty ? value : '$dataBuf\n$value';
            case 'event':
              eventBuf = value;
            case 'id':
              idBuf = value;
            case 'retry':
              final int? milliseconds = int.tryParse(value);
              if (milliseconds != null) {
                retryBuf = Duration(milliseconds: milliseconds);
              }
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!_closed) controller.addError(error, stackTrace);
        },
        onDone: () {
          emit();
          unawaited(controller.close());
        },
        cancelOnError: false,
      );
      controller.onCancel = () async {
        await _lineSubscription?.cancel();
      };
    } catch (error, stackTrace) {
      if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
        // A transport failure before receiving the HTTP response is not a
        // successful connection. Propagate it through `ready` so
        // SseReconnector does not reset its retry budget for a stream that
        // is already closing.
        _readyCompleter!.completeError(error, stackTrace);
      }
      if (!_closed && identical(_controller, controller)) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    if (_readyCompleter != null && !_readyCompleter!.isCompleted) {
      _readyCompleter!.complete();
    }
    await _lineSubscription?.cancel();
    _lineSubscription = null;
    if (_controller != null && !_controller!.isClosed) {
      await _controller!.close();
    }
    if (_activityController != null && !_activityController!.isClosed) {
      await _activityController!.close();
    }
    _controller = null;
    _activityController = null;
    if (_ownsHttpClient) {
      _httpClient?.close();
      _httpClient = null;
    }
  }
}
