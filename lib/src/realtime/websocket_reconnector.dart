import 'websocket_connection.dart';
import 'websocket_message.dart';

/// Auto-reconnecting wrapper. Wraps any
/// [WebSocketConnection] factory and retries
/// connection with exponential backoff when the
/// initial [start] fails.
///
/// Note: this reconnector retries the FIRST
/// connection only (during [start]). Mid-session
/// reconnects are NOT automatic — call [start]
/// again from the user's `onDone` handler.
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

  /// Underlying client. Null before [start] and
  /// during reconnects.
  WebSocketConnection? get client => _client;

  /// Broadcast [Stream] of incoming messages
  /// (forwarded from the underlying client).
  /// Throws [StateError] if [start] hasn't been
  /// called yet.
  Stream<WebSocketMessage> get messages {
    if (_client == null) {
      throw StateError('WebSocketReconnector not started.');
    }
    return _client!.messages;
  }

  /// Tries [maxAttempts] times to connect before
  /// giving up. The last error is re-thrown.
  Future<void> start() async {
    int attempt = 0;
    while (true) {
      try {
        _client = factory();
        await _client!.connect(url, headers: headers);
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
    if (_client != null) {
      await _client!.close();
      _client = null;
    }
  }
}
