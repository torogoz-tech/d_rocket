import 'dart:async';

import '../diagnostics/diagnostic_category.dart';
import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/drocket_diagnostics.dart';
import 'websocket_connection.dart';
import 'websocket_message.dart';
import 'websocket_reconnector_state.dart';

/// Auto-reconnecting wrapper for a [WebSocketConnection].
class WebSocketReconnector {
  WebSocketReconnector({
    required this.factory,
    required this.url,
    this.headers,
    this.headersProvider,
    this.onUnauthorized,
    Duration initialBackoff = const Duration(seconds: 1),
    int maxAttempts = 5,
    this.heartbeatInterval,
    WebSocketMessage? heartbeatMessage,
    this.inactivityTimeout,
  })  : _initialBackoff = initialBackoff,
        _maxAttempts = maxAttempts,
        heartbeatMessage =
            heartbeatMessage ?? WebSocketMessage.text('{"type":"ping"}'),
        assert(maxAttempts > 0);

  /// Factory that creates a new client for each connection.
  final WebSocketConnection Function() factory;

  /// URL to connect to.
  final Uri url;

  /// Static headers used when [headersProvider] is not configured.
  final Map<String, String>? headers;

  /// Gets fresh headers before every connection attempt.
  final FutureOr<Map<String, String>> Function()? headersProvider;

  /// Invoked once for a 401 response. Return true after refreshing the
  /// session to retry with headers from [headersProvider].
  final FutureOr<bool> Function()? onUnauthorized;

  /// Optional application-level heartbeat interval.
  final Duration? heartbeatInterval;

  /// Message sent by the heartbeat timer.
  final WebSocketMessage heartbeatMessage;

  /// Maximum time without inbound traffic before reconnecting.
  final Duration? inactivityTimeout;

  final Duration _initialBackoff;
  final int _maxAttempts;
  final StreamController<WebSocketMessage> _incoming =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<WebSocketReconnectorState> _states =
      StreamController<WebSocketReconnectorState>.broadcast(sync: true);

  WebSocketConnection? _client;
  StreamSubscription<WebSocketMessage>? _subscription;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  Timer? _inactivityTimer;
  Completer<void>? _retryCompleter;
  Future<void>? _connectionFuture;
  int _attempt = 0;
  int _generation = 0;
  int? _statusCode;
  Object? _lastError;
  StackTrace? _lastStackTrace;
  int? _lastCloseCode;
  String? _lastCloseReason;
  bool _stopped = true;
  bool _disposed = false;
  WebSocketReconnectorState _state = WebSocketReconnectorState.stopped;

  /// Underlying client, if a connection is active or connecting.
  WebSocketConnection? get client => _client;

  /// Broadcast stream of incoming messages.
  Stream<WebSocketMessage> get messages => _incoming.stream;

  /// Broadcast stream of lifecycle changes.
  Stream<WebSocketReconnectorState> get states => _states.stream;

  /// Current lifecycle state.
  WebSocketReconnectorState get state => _state;

  /// HTTP status reported by the most recent transport, if available.
  int? get statusCode => _statusCode;

  /// Last connection error, if a connection or retry failed.
  Object? get lastError => _lastError;

  /// Stack trace associated with [lastError].
  StackTrace? get lastStackTrace => _lastStackTrace;

  /// Close code reported by a transport, when available.
  int? get lastCloseCode => _lastCloseCode;

  /// Close reason reported by a transport, when available.
  String? get lastCloseReason => _lastCloseReason;

  /// Starts a connection and returns when the first connection succeeds.
  Future<void> start() {
    _ensureNotDisposed();
    if (!_stopped &&
        (_client?.isConnected == true || _connectionFuture != null)) {
      return _connectionFuture ?? Future<void>.value();
    }
    _stopped = false;
    final int generation = ++_generation;
    _attempt = 0;
    _lastError = null;
    _lastStackTrace = null;
    _lastCloseCode = null;
    _lastCloseReason = null;
    _connectionFuture = _connectLoop(generation, 0);
    return _connectionFuture!;
  }

  /// Stops all pending work and closes the current connection.
  Future<void> stop() async {
    if (_disposed) return;
    _stopped = true;
    ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryCompleter?.complete();
    _retryCompleter = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final WebSocketConnection? client = _client;
    _client = null;
    await client?.close();
    _emit(WebSocketReconnectorState.stopped);
  }

  /// Releases streams and stops the reconnector permanently.
  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    await _incoming.close();
    await _states.close();
  }

  Future<void> _connectLoop(int generation, int failures) async {
    bool unauthorizedHandled = false;
    while (_isCurrent(generation)) {
      WebSocketConnection? candidate;
      try {
        _emit(WebSocketReconnectorState.connecting);
        final Map<String, String>? currentHeaders =
            headersProvider == null ? headers : await headersProvider!();
        candidate = factory();
        _client = candidate;
        await candidate.connect(url, headers: currentHeaders);
        if (!_isCurrent(generation)) {
          await candidate.close();
          return;
        }
        _statusCode = _readStatusCode(candidate);
        _attempt = 0;
        _emit(WebSocketReconnectorState.connected);
        _subscription = candidate.messages.listen(
          (message) {
            if (_isCurrent(generation)) {
              _resetInactivityTimer(generation);
              _incoming.add(message);
            }
          },
          onError: (Object error, StackTrace stackTrace) =>
              _handleDisconnect(generation, error, stackTrace),
          onDone: () => _handleDisconnect(generation),
        );
        _startHeartbeat(generation);
        _resetInactivityTimer(generation);
        return;
      } catch (error, stackTrace) {
        if (!_isCurrent(generation)) return;
        _lastError = error;
        _lastStackTrace = stackTrace;
        _statusCode = _readStatusCode(candidate);
        _captureCloseDetails(candidate);
        await _closeCandidate(candidate);
        if (_statusCode == 401 && !unauthorizedHandled) {
          unauthorizedHandled = true;
          final bool recovered = await _recoverUnauthorized();
          if (recovered && _isCurrent(generation)) continue;
          _emit(WebSocketReconnectorState.failed);
          Error.throwWithStackTrace(error, stackTrace);
        }
        if (_statusCode == 403) {
          _emit(WebSocketReconnectorState.failed);
          Error.throwWithStackTrace(error, stackTrace);
        }
        failures++;
        _attempt = failures;
        if (failures >= _maxAttempts) {
          _emit(WebSocketReconnectorState.failed);
          Error.throwWithStackTrace(error, stackTrace);
        }
        _emit(WebSocketReconnectorState.retrying);
        await _wait(_backoff(failures), generation);
      }
    }
  }

  Future<bool> _recoverUnauthorized() async {
    final FutureOr<bool> Function()? callback = onUnauthorized;
    if (callback == null) return false;
    try {
      return await callback();
    } catch (_) {
      return false;
    }
  }

  void _handleDisconnect(int generation,
      [Object? error, StackTrace? stackTrace]) {
    if (!_isCurrent(generation) || _retryTimer != null) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    final WebSocketConnection? oldClient = _client;
    _client = null;
    if (error != null) {
      _lastError = error;
      _lastStackTrace = stackTrace;
    }
    _captureCloseDetails(oldClient);
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(oldClient?.close());
    final int nextAttempt = _attempt + 1;
    _attempt = nextAttempt;
    if (nextAttempt >= _maxAttempts) {
      _emit(WebSocketReconnectorState.failed);
      return;
    }
    _emit(WebSocketReconnectorState.retrying);
    _retryTimer = Timer(_backoff(nextAttempt), () {
      _retryTimer = null;
      _connectionFuture = _connectLoop(generation, nextAttempt);
    });
  }

  void _startHeartbeat(int generation) {
    _heartbeatTimer?.cancel();
    final Duration? interval = heartbeatInterval;
    if (interval == null || interval <= Duration.zero) return;
    _heartbeatTimer = Timer.periodic(interval, (_) async {
      final WebSocketConnection? current = _client;
      if (!_isCurrent(generation) || current == null || !current.isConnected) {
        return;
      }
      try {
        await current.send(heartbeatMessage);
        _resetInactivityTimer(generation);
      } catch (error, stackTrace) {
        _handleDisconnect(generation, error, stackTrace);
      }
    });
  }

  void _resetInactivityTimer(int generation) {
    _inactivityTimer?.cancel();
    final Duration? timeout = inactivityTimeout;
    if (timeout == null || timeout <= Duration.zero) return;
    _inactivityTimer = Timer(timeout, () {
      if (_isCurrent(generation)) {
        _handleDisconnect(generation);
      }
    });
  }

  Future<void> _wait(Duration duration, int generation) async {
    if (!_isCurrent(generation)) return;
    final Completer<void> completer = Completer<void>();
    _retryCompleter = completer;
    _retryTimer = Timer(duration, () {
      _retryTimer = null;
      _retryCompleter = null;
      completer.complete();
    });
    await completer.future;
  }

  Future<void> _closeCandidate(WebSocketConnection? candidate) async {
    if (candidate == null) return;
    if (identical(_client, candidate)) _client = null;
    await candidate.close();
  }

  void _captureCloseDetails(WebSocketConnection? candidate) {
    if (candidate == null) return;
    final Object? code = _readOptional(candidate, 'closeCode');
    final Object? reason = _readOptional(candidate, 'closeReason');
    if (code is int) _lastCloseCode = code;
    if (reason is String) _lastCloseReason = reason;
  }

  int? _readStatusCode(WebSocketConnection? candidate) {
    final Object? statusCode = _readOptional(candidate, 'statusCode');
    return statusCode is int ? statusCode : null;
  }

  Object? _readOptional(WebSocketConnection? candidate, String member) {
    if (candidate == null) return null;
    try {
      final dynamic value = candidate;
      return member == 'statusCode'
          ? value.statusCode
          : member == 'closeCode'
              ? value.closeCode
              : value.closeReason;
    } on NoSuchMethodError {
      return null;
    }
  }

  Duration _backoff(int attempt) => _initialBackoff * (1 << (attempt - 1));

  bool _isCurrent(int generation) =>
      !_disposed && !_stopped && generation == _generation;

  void _emit(WebSocketReconnectorState next) {
    _state = next;
    final DrocketDiagnostics diagnostics = DrocketDiagnostics.instance;
    if (diagnostics.enabled) {
      diagnostics.record(
        DiagnosticEvent(
          correlationId: '${url.toString()}-${identityHashCode(this)}',
          category: DiagnosticCategory.realtime,
          operation: 'websocket.state',
          startedAt: DateTime.now(),
          success: next != WebSocketReconnectorState.failed,
          statusCode: _statusCode,
          error: diagnostics.includeSensitiveData
              ? _lastError?.toString()
              : _lastError?.runtimeType.toString(),
          metadata: <String, Object?>{
            'state': next.name,
            'attempt': _attempt,
            'url': url.toString(),
            if (_lastCloseCode != null) 'closeCode': _lastCloseCode,
            if (_lastCloseReason != null) 'closeReason': _lastCloseReason,
          },
        ),
      );
    }
    if (!_states.isClosed) _states.add(next);
  }

  void _ensureNotDisposed() {
    if (_disposed) throw StateError('WebSocketReconnector is disposed');
  }
}
