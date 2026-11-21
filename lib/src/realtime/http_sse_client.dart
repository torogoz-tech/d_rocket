import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sse_connection.dart';
import 'sse_event.dart';
import 'sse_http_exception.dart';
import 'sse_interceptor.dart';

/// An SSE client backed by `package:http`.
class HttpSseClient implements SseConnection {
  HttpSseClient({
    http.Client? httpClient,
    this.defaultHeaders = const <String, String>{},
    this.interceptors = const <SseInterceptor>[],
    this.connectTimeout = const Duration(seconds: 30),
    this.followRedirects = true,
    this.validateContentType = true,
  })  : _httpClient = httpClient,
        _ownsHttpClient = httpClient == null;

  /// Headers applied to every connection before per-connection headers.
  final Map<String, String> defaultHeaders;

  /// Interceptors invoked for requests, responses and connection failures.
  final List<SseInterceptor> interceptors;

  /// Maximum time allowed to receive the initial HTTP response.
  /// Set to `null` to disable the timeout.
  final Duration? connectTimeout;

  /// Whether HTTP redirects should be followed by the underlying request.
  final bool followRedirects;

  /// Whether successful responses must declare `text/event-stream`.
  final bool validateContentType;
  late final CompositeSseInterceptor _interceptorChain =
      CompositeSseInterceptor(interceptors);

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
        ...defaultHeaders,
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...?headers,
      };
      if (lastEventId != null) allHeaders['Last-Event-ID'] = lastEventId;

      http.BaseRequest request = http.Request('GET', url)
        ..followRedirects = followRedirects
        ..headers.addAll(allHeaders);
      request = await _interceptorChain.onRequest(request);
      final Future<http.StreamedResponse> responseFuture = _httpClient!.send(
        request,
      );
      final http.StreamedResponse response = connectTimeout == null
          ? await responseFuture
          : await responseFuture.timeout(connectTimeout!);
      if (_closed || !identical(_controller, controller)) return;
      final http.StreamedResponse interceptedResponse =
          await _interceptorChain.onResponse(response);
      _statusCode = interceptedResponse.statusCode;
      _readyCompleter?.complete();
      if (interceptedResponse.statusCode != 200) {
        controller.addError(SseHttpException(interceptedResponse.statusCode));
        await controller.close();
        return;
      }
      if (validateContentType && !_isEventStream(interceptedResponse)) {
        throw const FormatException('Expected text/event-stream');
      }

      final Stream<String> lineStream = interceptedResponse.stream
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
          unawaited(_interceptorChain.onError(error, stackTrace));
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
      if (error is TimeoutException && _ownsHttpClient) {
        _httpClient?.close();
        _httpClient = null;
      }
      await _interceptorChain.onError(error, stackTrace);
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
      // A single-subscription controller waits for a listener before its
      // close future completes. Closing must not depend on the consumer
      // having listened, especially while a connection attempt is pending.
      unawaited(_controller!.close());
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

  bool _isEventStream(http.StreamedResponse response) {
    final String contentType = response.headers['content-type'] ?? '';
    final String mediaType = contentType.split(';').first.trim().toLowerCase();
    return mediaType == 'text/event-stream';
  }
}
