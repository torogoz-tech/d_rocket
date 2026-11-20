import 'dart:async';

import 'sse_connection.dart';
import 'sse_event.dart';
import 'sse_http_exception.dart';
import 'sse_reconnector_state.dart';

/// Auto-reconnecting SSE stream with authentication and cursor support.
class SseReconnector {
  SseReconnector({
    required this.factory,
    required this.url,
    this.headers,
    this.headersProvider,
    this.onUnauthorized,
    Duration initialBackoff = const Duration(seconds: 1),
    int maxAttempts = 5,
    this.inactivityTimeout,
    this.manualAcknowledge = false,
  })  : _initialBackoff = initialBackoff,
        _maxAttempts = maxAttempts;

  final SseConnection Function() factory;
  final Uri url;
  final Map<String, String>? headers;
  final FutureOr<Map<String, String>> Function()? headersProvider;
  final FutureOr<bool> Function()? onUnauthorized;
  final Duration? inactivityTimeout;
  final bool manualAcknowledge;
  final Duration _initialBackoff;
  final int _maxAttempts;
  final StreamController<SseEvent> _events =
      StreamController<SseEvent>.broadcast();
  final StreamController<SseReconnectorState> _states =
      StreamController<SseReconnectorState>.broadcast();

  StreamSubscription<SseEvent>? _subscription;
  StreamSubscription<void>? _activitySubscription;
  Timer? _retryTimer;
  Timer? _inactivityTimer;
  SseConnection? _connection;
  String? _lastEventId;
  Duration? _serverRetry;
  int _attempt = 0;
  int _generation = 0;
  bool _stopped = true;
  bool _disposed = false;
  bool _connected = false;
  SseReconnectorState _state = SseReconnectorState.stopped;
  int? _statusCode;

  Stream<SseEvent> get events => _events.stream;
  Stream<SseReconnectorState> get states => _states.stream;
  bool get isConnected => _connected;
  String? get lastEventId => _lastEventId;
  int? get statusCode => _statusCode;
  SseReconnectorState get state => _state;

  Future<void> start() async {
    if (_disposed || !_stopped) return;
    _stopped = false;
    final int generation = ++_generation;
    await _connect(generation);
  }

  Future<void> stop() async {
    if (_disposed) return;
    _stopped = true;
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _cancelConnection();
    _setState(SseReconnectorState.stopped);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _events.close();
    await _states.close();
  }

  void clearLastEventId() => _lastEventId = null;

  /// Commits an event id after its payload has been processed successfully.
  void acknowledge(SseEvent event) {
    if (event.id != null) _lastEventId = event.id;
  }

  void acknowledgeEventId(String id) => _lastEventId = id;

  Future<void> _connect(int generation) async {
    if (!_isCurrent(generation)) return;
    _setState(SseReconnectorState.connecting);
    final SseConnection connection = factory();
    _connection = connection;
    try {
      final Map<String, String> resolvedHeaders = <String, String>{
        ...?headers,
        ...?await headersProvider?.call(),
      };
      if (!_isCurrent(generation)) {
        await connection.close();
        return;
      }
      final Stream<SseEvent> stream = connection.connect(
        url,
        headers: resolvedHeaders.isEmpty ? null : resolvedHeaders,
        lastEventId: _lastEventId,
      );
      await connection.ready;
      if (!_isCurrent(generation)) {
        await connection.close();
        return;
      }
      _statusCode = connection.statusCode;
      if (_statusCode != null && _statusCode != 200) {
        await _handleHttpFailure(connection, generation);
        return;
      }
      _attempt = 0;
      _connected = true;
      _setState(SseReconnectorState.connected);
      _armInactivityTimer(connection, generation);
      _activitySubscription = connection.activity.listen(
        (_) => _armInactivityTimer(connection, generation),
      );
      _subscription = stream.listen(
        (SseEvent event) => _onEvent(event, generation, connection),
        onError: (Object error, StackTrace stackTrace) {
          _onError(error, stackTrace, generation, connection);
        },
        onDone: () => _scheduleReconnect(connection, generation),
      );
    } catch (error, stackTrace) {
      _events.addError(error, stackTrace);
      await _scheduleReconnect(connection, generation);
    }
  }

  Future<void> _handleHttpFailure(
    SseConnection connection,
    int generation,
  ) async {
    final int code = connection.statusCode!;
    final SseHttpException error = SseHttpException(code);
    _statusCode = code;
    if (code == 401 && onUnauthorized != null) {
      bool refreshed = false;
      try {
        refreshed = await onUnauthorized!.call();
      } catch (error, stackTrace) {
        _events.addError(error, stackTrace);
      }
      if (refreshed && _isCurrent(generation)) {
        await _scheduleReconnect(connection, generation);
        return;
      }
    }
    _events.addError(error, StackTrace.current);
    if (code == 403 || code == 401) {
      _stopped = true;
      ++_generation;
      _connected = false;
      _setState(SseReconnectorState.failed);
      await _cancelConnection();
      return;
    }
    await _scheduleReconnect(connection, generation);
  }

  void _onEvent(
    SseEvent event,
    int generation,
    SseConnection connection,
  ) {
    if (!_isCurrent(generation) || !identical(_connection, connection)) return;
    _armInactivityTimer(connection, generation);
    if (!manualAcknowledge && event.id != null) _lastEventId = event.id;
    if (event.retry != null) _serverRetry = event.retry;
    _events.add(event);
  }

  void _onError(
    Object error,
    StackTrace stackTrace,
    int generation,
    SseConnection connection,
  ) {
    if (!_isCurrent(generation) || !identical(_connection, connection)) return;
    _connected = false;
    _events.addError(error, stackTrace);
    unawaited(_scheduleReconnect(connection, generation));
  }

  Future<void> _scheduleReconnect(
    SseConnection connection,
    int generation,
  ) async {
    if (!_isCurrent(generation) || _retryTimer != null) return;
    _connected = false;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _cancelConnection(closeOnly: connection);
    if (!_isCurrent(generation)) return;
    if (_attempt >= _maxAttempts) {
      _setState(SseReconnectorState.failed);
      return;
    }
    _attempt++;
    final Duration delay = _serverRetry ?? _backoffFor(_attempt);
    _setState(SseReconnectorState.retrying);
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect(generation));
    });
  }

  Duration _backoffFor(int attempt) => _initialBackoff * (1 << (attempt - 1));

  void _armInactivityTimer(SseConnection connection, int generation) {
    final Duration? timeout = inactivityTimeout;
    if (timeout == null || timeout <= Duration.zero) return;
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(timeout, () {
      if (_isCurrent(generation) && identical(_connection, connection)) {
        unawaited(_scheduleReconnect(connection, generation));
      }
    });
  }

  Future<void> _cancelConnection({SseConnection? closeOnly}) async {
    final SseConnection? connection = closeOnly ?? _connection;
    await _subscription?.cancel();
    _subscription = null;
    await _activitySubscription?.cancel();
    _activitySubscription = null;
    if (identical(_connection, connection)) _connection = null;
    if (connection != null) await connection.close();
  }

  bool _isCurrent(int generation) =>
      !_disposed && !_stopped && generation == _generation;

  void _setState(SseReconnectorState value) {
    if (_state == value) return;
    _state = value;
    if (!_states.isClosed) _states.add(value);
  }
}
