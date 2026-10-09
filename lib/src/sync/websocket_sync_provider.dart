/// 2.0.0 — bi-directional sync over WebSocket.
///
/// The [WebSocketSyncProvider] is a
/// [SyncProvider] that uses a WebSocket to
/// receive server-pushed changes (in addition
/// to the usual push/pull round-trip). This
/// means the server can tell the client
/// "row X in table Y changed" without waiting
/// for the next periodic sync.
///
/// ## Architecture
///
/// ```
/// +-----------------+   WS push    +-----------------+
/// |     Server      |  ──────────► |  WS listener    |
/// +-----------------+              +-----------------+
///                                          │ invoke
///                                          ▼
///                                  +-----------------+
///                                  |  ServerPush     |
///                                  |  handler        |
///                                  +-----------------+
///                                          │ apply
///                                          ▼
///                                  +-----------------+
///                                  |  DbContext      |
///                                  |  (applyRemote)  |
///                                  +-----------------+
/// ```
///
/// ## Example
///
/// ```dart
/// final ws = WebSocketSyncProvider(
///   url: Uri.parse('wss://api.example.com/sync'),
///   authHeader: 'Bearer ...',
///   pushHandler: (change) async {
///     // Apply the server-pushed change.
///     // (Usually this is just `ctx.applyRemote(change)`)
///   },
/// );
/// await ws.connect();
/// // On disconnect:
/// await ws.close();
/// ```
library;

import 'dart:async';
import 'dart:convert';

import '../realtime/websocket_connection.dart';
import '../realtime/websocket_message.dart';
import '../realtime/websocket_message_type.dart';
import 'sync_change.dart';
import 'sync_envelope.dart';
import 'sync_provider.dart';

/// A server-pushed [SyncChange] received over
/// the WebSocket. Includes the time it was
/// received (for telemetry + clock-skew
/// detection).
class PushedSyncChange {
  /// Creates a [PushedSyncChange].
  PushedSyncChange({
    required this.change,
    required this.receivedAt,
    this.originServerId,
  });

  /// The change.
  final SyncChange change;

  /// When the client received it.
  final DateTime receivedAt;

  /// The server id that originated the push
  /// (used for multi-server setups, e.g.
  /// sharded sync).
  final String? originServerId;
}

/// A handler for server-pushed changes. Called
/// once per change, on the main isolate.
///
/// The handler is expected to be quick
/// (apply the change to the local DB and
/// return). Long-running work should be
/// dispatched to a worker isolate.
typedef ServerPushHandler = Future<void> Function(PushedSyncChange change);

/// A WebSocket-based [SyncProvider] that also
/// receives server-pushed changes.
///
/// The push side is **fire-and-forget** — the
/// server pushes changes, the client applies
/// them. The push side does NOT use the
/// [syncAsync] / pull API; the pull API is
/// still there for the initial sync and for
/// back-fills.
class WebSocketSyncProvider implements SyncProvider {
  /// Creates a [WebSocketSyncProvider].
  ///
  /// [url] is the WebSocket endpoint. [auth]
  /// is an optional function that returns the
  /// current auth header value (called on
  /// reconnect). [pushHandler] is invoked for
  /// each server-pushed change. [channel] is
  /// an optional WebSocket channel factory
  /// (defaults to
  /// `WebSocketChannel.connect`); useful for
  /// tests.
  WebSocketSyncProvider({
    required this.url,
    required this.pushHandler,
    Future<String?> Function()? auth,
    Future<Object> Function(Uri)? channel,
    WebSocketConnection Function()? connectionFactory,
    Duration reconnectBackoff = const Duration(seconds: 1),
    int maxReconnectAttempts = 5,
  })  : _auth = auth,
        _channelFactory = channel,
        _connectionFactory = connectionFactory,
        _reconnectBackoff = reconnectBackoff,
        _maxReconnectAttempts = maxReconnectAttempts;

  /// The WebSocket URL.
  final Uri url;

  /// Handler for server-pushed changes.
  final ServerPushHandler pushHandler;

  final Future<String?> Function()? _auth;
  final Future<Object> Function(Uri)? _channelFactory;
  final WebSocketConnection Function()? _connectionFactory;
  final Duration _reconnectBackoff;
  final int _maxReconnectAttempts;

  /// The current connection state.
  final StreamController<bool> _connected =
      StreamController<bool>.broadcast(sync: true);
  bool _isConnected = false;

  WebSocketConnection? _connection;
  StreamSubscription<WebSocketMessage>? _messageSub;
  Timer? _reconnectTimer;
  Completer<SyncEnvelope>? _pendingSync;
  Completer<int>? _pendingWatermark;
  int _requestSequence = 0;
  int _reconnectAttempts = 0;
  bool _manualClose = false;

  /// `true` if the WebSocket is currently
  /// connected.
  bool get isConnected => _isConnected;

  /// A broadcast stream of connection state
  /// changes. New subscribers receive the
  /// current state as the first event
  /// (replay-1).
  Stream<bool> get connected {
    late StreamController<bool> wrapper;
    StreamSubscription<bool>? sub;
    wrapper = StreamController<bool>(
      onListen: () {
        wrapper.add(_isConnected);
        sub = _connected.stream.listen(wrapper.add);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return wrapper.stream;
  }

  /// Opens the WebSocket connection. Safe to
  /// call multiple times — subsequent calls
  /// are no-ops.
  Future<void> connect() async {
    if (_isConnected) return;
    _manualClose = false;
    final WebSocketConnection connection;
    if (_connectionFactory != null) {
      connection = _connectionFactory();
    } else if (_channelFactory != null) {
      final Object value = await _channelFactory(url);
      if (value is! WebSocketConnection) {
        throw ArgumentError.value(
          value,
          'channel',
          'The channel factory must return a WebSocketConnection.',
        );
      }
      connection = value;
    } else {
      return;
    }

    final Map<String, String> headers = <String, String>{};
    if (_auth != null) {
      final String? token = await _auth();
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    await connection.connect(url, headers: headers.isEmpty ? null : headers);
    _connection = connection;
    _isConnected = true;
    _reconnectAttempts = 0;
    _connected.add(true);
    _messageSub = connection.messages.listen(
      _handleMessage,
      onError: _handleDisconnect,
      onDone: _handleDisconnect,
    );
  }

  /// Closes the WebSocket connection.
  Future<void> close() async {
    _manualClose = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _messageSub?.cancel();
    _messageSub = null;
    await _connection?.close();
    _connection = null;
    _setDisconnected();
    _pendingSync?.completeError(StateError('WebSocket connection closed.'));
    _pendingWatermark
        ?.completeError(StateError('WebSocket connection closed.'));
    _pendingSync = null;
    _pendingWatermark = null;
  }

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    await _ensureConnected();
    final WebSocketConnection? connection = _connection;
    if (connection == null) {
      throw StateError('WebSocketSyncProvider is not connected.');
    }
    if (_pendingSync != null) {
      throw StateError('A WebSocket sync request is already in progress.');
    }
    final Completer<SyncEnvelope> pending = Completer<SyncEnvelope>();
    _pendingSync = pending;
    await connection.send(
      WebSocketMessage.text(
        jsonEncode(<String, Object?>{
          'type': 'sync.request',
          'requestId': _nextRequestId(),
          'envelope': envelope.toJson(),
        }),
      ),
    );
    try {
      return await pending.future;
    } finally {
      if (identical(_pendingSync, pending)) _pendingSync = null;
    }
  }

  @override
  Future<int> currentWatermarkAsync() async {
    if (!_isConnected &&
        _connectionFactory == null &&
        _channelFactory == null) {
      return 0;
    }
    await _ensureConnected();
    final WebSocketConnection? connection = _connection;
    if (connection == null) {
      throw StateError('WebSocketSyncProvider is not connected.');
    }
    if (_pendingWatermark != null) {
      throw StateError(
        'A WebSocket watermark request is already in progress.',
      );
    }
    final Completer<int> pending = Completer<int>();
    _pendingWatermark = pending;
    await connection.send(
      WebSocketMessage.text(
        jsonEncode(<String, Object?>{
          'type': 'sync.watermark.request',
          'requestId': _nextRequestId(),
        }),
      ),
    );
    try {
      return await pending.future;
    } finally {
      if (identical(_pendingWatermark, pending)) _pendingWatermark = null;
    }
  }

  Future<void> _ensureConnected() async {
    if (!_isConnected) await connect();
    if (!_isConnected) {
      throw StateError(
        'WebSocketSyncProvider has no connection factory. '
        'Provide connectionFactory or channel.',
      );
    }
  }

  String _nextRequestId() => 'd_rocket_${++_requestSequence}';

  void _handleMessage(WebSocketMessage message) {
    if (message.type != WebSocketMessageType.text || message.text == null) {
      return;
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(message.text!);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;
    final Map<String, Object?> json = decoded.cast<String, Object?>();
    switch (json['type']) {
      case 'sync.response':
        final dynamic raw = json['envelope'];
        if (raw is Map && _pendingSync != null) {
          _pendingSync!.complete(
            SyncEnvelope.fromJson(raw.cast<String, Object?>()),
          );
        }
      case 'sync.watermark.response':
        final dynamic raw = json['watermark'];
        if (raw is num && _pendingWatermark != null) {
          _pendingWatermark!.complete(raw.toInt());
        }
      case 'sync.change':
        final dynamic raw = json['change'];
        if (raw is Map) {
          unawaited(pushHandler(PushedSyncChange(
            change: SyncChange.fromJson(raw.cast<String, Object?>()),
            receivedAt: DateTime.now().toUtc(),
            originServerId: json['originServerId'] as String?,
          )));
        }
    }
  }

  void _handleDisconnect([Object? error, StackTrace? stackTrace]) {
    if (_manualClose) return;
    _setDisconnected();
    if (_reconnectAttempts >= _maxReconnectAttempts ||
        (_connectionFactory == null && _channelFactory == null)) {
      return;
    }
    _reconnectAttempts++;
    final Duration delay = _reconnectBackoff * (1 << (_reconnectAttempts - 1));
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
      } catch (_) {
        _handleDisconnect();
      }
    });
  }

  void _setDisconnected() {
    if (_isConnected) {
      _isConnected = false;
      _connected.add(false);
    }
  }
}
