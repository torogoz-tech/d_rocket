import 'dart:async';

import 'websocket_connection.dart';
import 'websocket_message.dart';

/// Auto-reconnecting wrapper. Wraps any
/// [WebSocketConnection] factory and retries
/// connection with exponential backoff when the
/// initial [start] fails.
///
/// Mid-session disconnects are retried automatically
/// until [maxAttempts] is reached or [stop] is called.
class WebSocketReconnector {
  WebSocketReconnector({
    required this.factory,
    required this.url,
    this.headers,
    Duration initialBackoff = const Duration(seconds: 1),
    int maxAttempts = 5,
  })  : _initialBackoff = initialBackoff,
        _maxAttempts = maxAttempts;

  /// Factory that creates a new client on each
  /// (re)connect.
  final WebSocketConnection Function() factory;

  /// URL to connect to.
  final Uri url;

  /// Optional headers (e.g. for auth).
  final Map<String, String>? headers;

  final Duration _initialBackoff;
  final int _maxAttempts;

  WebSocketConnection? _client;
  StreamSubscription<WebSocketMessage>? _subscription;
  final StreamController<WebSocketMessage> _incoming =
      StreamController<WebSocketMessage>.broadcast();
  Timer? _retryTimer;
  int _attempt = 0;
  bool _stopped = true;

  /// Underlying client. Null before [start] and
  /// during reconnects.
  WebSocketConnection? get client => _client;

  /// Broadcast [Stream] of incoming messages.
  Stream<WebSocketMessage> get messages => _incoming.stream;

  /// Tries [maxAttempts] times to connect before
  /// giving up. The last error is re-thrown.
  Future<void> start() async {
    if (!_stopped && _client?.isConnected == true) return;
    _stopped = false;
    int attempt = 0;
    while (true) {
      try {
        _client = factory();
        await _client!.connect(url, headers: headers);
        _attempt = 0;
        _subscription = _client!.messages.listen(
          _incoming.add,
          onError: _handleDisconnect,
          onDone: _handleDisconnect,
        );
        return;
      } catch (e) {
        attempt++;
        if (attempt >= _maxAttempts) rethrow;
        // Exponential: 1s, 2s, 4s, 8s, 16s.
        final Duration delay = _initialBackoff * (1 << (attempt - 1));
        await Future<void>.delayed(delay);
      }
    }
  }

  /// Stops the reconnector. Closes the underlying
  /// client (if any).
  Future<void> stop() async {
    _stopped = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _client?.close();
    _client = null;
  }

  void _handleDisconnect([Object? error, StackTrace? stackTrace]) {
    if (_stopped || _retryTimer != null) return;
    _client = null;
    if (_attempt >= _maxAttempts) return;
    _attempt++;
    final Duration delay = _initialBackoff * (1 << (_attempt - 1));
    _retryTimer = Timer(delay, () async {
      _retryTimer = null;
      try {
        await start();
      } catch (_) {
        _handleDisconnect();
      }
    });
  }
}
