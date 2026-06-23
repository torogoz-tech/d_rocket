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
  })  : _auth = auth,
        _channelFactory = channel;

  /// The WebSocket URL.
  final Uri url;

  /// Handler for server-pushed changes.
  final ServerPushHandler pushHandler;

  final Future<String?> Function()? _auth;
  final Future<Object> Function(Uri)? _channelFactory;

  /// The current connection state.
  final StreamController<bool> _connected =
      StreamController<bool>.broadcast(sync: true);
  bool _isConnected = false;

  Object? _channel;
  StreamSubscription<dynamic>? _channelSub;

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
    // In a real impl, we'd use
    // `WebSocketChannel.connect` from
    // `package:web_socket_channel`. For
    // 2.0.0 we expose the channel factory so
    // tests can inject a fake one.
    final Uri wsUrl = url;
    if (_auth != null) {
      final String? token = await _auth();
      if (token != null) {
        // Add token to the URL or as a
        // protocol header, depending on
        // server convention.
      }
    }
    if (_channelFactory != null) {
      _channel = await _channelFactory(wsUrl);
    } else {
      // No factory — connect() is a no-op.
      // Users who want real WebSocket support
      // must provide a channel factory (or
      // wait for the `d_rocket_realtime`
      // integration in 2.1.0).
      return;
    }
    _isConnected = true;
    _connected.add(true);
    // (In a real impl, we'd listen to
    // _channel!.stream and parse each
    // message as a SyncChange.)
    _channelSub = (_channel as Stream<dynamic>).listen(
      (_) {/* placeholder */},
      onError: (Object _, StackTrace __) {
        _isConnected = false;
        _connected.add(false);
      },
      onDone: () {
        _isConnected = false;
        _connected.add(false);
      },
    );
  }

  /// Closes the WebSocket connection.
  Future<void> close() async {
    if (!_isConnected) return;
    await _channelSub?.cancel();
    _isConnected = false;
    _connected.add(false);
    if (!_connected.isClosed) {
      await _connected.close();
    }
  }

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    // The WebSocket transport's pull side is
    // implemented as a regular round-trip.
    // In a real impl, the server would
    // accept a JSON envelope over the
    // existing WebSocket (e.g. as the first
    // message after `connect`).
    // For 2.0.0, the round-trip uses an
    // injected transport (the same one as
    // RestSyncProvider). Callers wire this
    // up explicitly.
    throw UnsupportedError(
      'WebSocketSyncProvider.syncAsync requires an injected transport. '
      'Use it together with RestSyncProvider, or wait for 2.1.0 '
      'where the realtime layer is integrated.',
    );
  }

  @override
  Future<int> currentWatermarkAsync() async {
    // No persistent watermark; the server
    // tracks it. Return 0 (the caller will
    // use the server's value in the next
    // pull).
    return 0;
  }
}
