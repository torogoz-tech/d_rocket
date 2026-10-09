import 'dart:async';

import 'sse_connection.dart';
import 'sse_event.dart';

/// Auto-reconnecting SSE stream with Last-Event-ID resume support.
class SseReconnector {
  SseReconnector({
    required this.factory,
    required this.url,
    this.headers,
    Duration initialBackoff = const Duration(seconds: 1),
    int maxAttempts = 5,
  })  : _initialBackoff = initialBackoff,
        _maxAttempts = maxAttempts;

  /// Creates a fresh connection for every attempt.
  final SseConnection Function() factory;

  /// SSE endpoint.
  final Uri url;

  /// Optional headers sent on every attempt.
  final Map<String, String>? headers;

  final Duration _initialBackoff;
  final int _maxAttempts;
  final StreamController<SseEvent> _events =
      StreamController<SseEvent>.broadcast();
  StreamSubscription<SseEvent>? _subscription;
  Timer? _retryTimer;
  String? _lastEventId;
  Duration? _serverRetry;
  int _attempt = 0;
  bool _stopped = true;
  bool _connected = false;

  /// Events received from the current and subsequent connections.
  Stream<SseEvent> get events => _events.stream;

  /// Whether the current SSE connection is open.
  bool get isConnected => _connected;

  /// The last event id received, sent as Last-Event-ID on reconnect.
  String? get lastEventId => _lastEventId;

  /// Starts the connection lifecycle.
  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    await _connect();
  }

  /// Stops reconnecting and closes the active connection.
  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _connected = false;
  }

  Future<void> _connect() async {
    if (_stopped) return;
    final SseConnection connection = factory();
    try {
      final Stream<SseEvent> stream = connection.connect(
        url,
        headers: headers,
        lastEventId: _lastEventId,
      );
      _connected = true;
      _attempt = 0;
      _subscription = stream.listen(
        _onEvent,
        onError: _onError,
        onDone: () => _scheduleReconnect(connection),
      );
    } catch (error, stackTrace) {
      _events.addError(error, stackTrace);
      await _scheduleReconnect(connection);
    }
  }

  void _onEvent(SseEvent event) {
    _connected = true;
    if (event.id != null) _lastEventId = event.id;
    if (event.retry != null) _serverRetry = event.retry;
    _events.add(event);
  }

  void _onError(Object error, StackTrace stackTrace) {
    _connected = false;
    _events.addError(error, stackTrace);
  }

  Future<void> _scheduleReconnect(SseConnection connection) async {
    if (_stopped || _retryTimer != null) return;
    _connected = false;
    await connection.close();
    if (_attempt >= _maxAttempts) return;
    _attempt++;
    final Duration delay =
        _serverRetry ?? _initialBackoff * (1 << (_attempt - 1));
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      await _connect();
    });
  }
}
