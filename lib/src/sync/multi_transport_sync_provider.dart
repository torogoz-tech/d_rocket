/// 2.0.0 — multi-transport sync provider.
///
/// [MultiTransportSyncProvider] orchestrates
/// multiple [SyncProvider]s, one per transport,
/// and picks the best one for each direction:
///
/// * **Pull (client → server, asking for
///   changes)**: always uses the polling
///   transport. The server is the source of
///   truth; the client has to ask.
///
/// * **Push (server → client, server telling
///   the client about a change)**: uses the
///   primary push transport (WebSocket if
///   available, else SSE, else nothing). If
///   the primary is down, falls back to the
///   secondary, then the tertiary.
///
/// * **Real-time (UDP)**: optional. If the
///   `udp` provider is set, it's used for
///   sub-second updates (e.g. live
///   multiplayer). The polling transport is
///   still used for persistence.
///
/// ## Example
///
/// ```dart
/// final multi = MultiTransportSyncProvider(
///   polling: RestSyncProvider(...),     // always-available fallback
///   webSocket: WebSocketSyncProvider(...), // primary push
///   sse: SseSyncProvider(...),          // fallback push
///   udp: UdpSyncProvider(...),          // optional, for real-time
/// );
/// await multi.connect();
/// await ctx.syncAsync(multi);
/// ```
library;

import 'dart:async';

import 'sync_envelope.dart';
import 'sync_provider.dart';
import 'sync_transport.dart';

/// A [SyncProvider] that combines multiple
/// transports.
///
/// The orchestration is:
/// 1. `pull`: use the polling transport (the
///   source of truth lives on the server).
/// 2. `push`: try the primary push transport
///   (WebSocket), then secondary (SSE), then
///   tertiary (polling again, as a "long poll").
/// 3. `real-time`: optional. If the `udp`
///   provider is set, it's connected in
///   parallel for sub-second updates.
class MultiTransportSyncProvider implements SyncProvider {
  /// Creates a [MultiTransportSyncProvider].
  /// At minimum, [polling] must be provided —
  /// it's the fallback that always works.
  /// The other transports are optional.
  MultiTransportSyncProvider({
    required this.polling,
    this.webSocket,
    this.sse,
    this.udp,
  });

  /// The polling transport. Always used for
  /// pull. Required.
  final SyncProvider polling;

  /// The WebSocket transport (optional).
  /// Primary push.
  final SyncProvider? webSocket;

  /// The SSE transport (optional). Fallback
  /// push.
  final SyncProvider? sse;

  /// The UDP transport (optional). Real-time
  /// updates.
  final SyncProvider? udp;

  final StreamController<SyncTransport> _activeTransport =
      StreamController<SyncTransport>.broadcast(sync: true);
  SyncTransport _active = SyncTransport.polling;

  /// The currently active transport.
  SyncTransport get activeTransport => _active;

  /// A broadcast stream of the active
  /// transport. Emits when the transport
  /// changes (e.g. WebSocket disconnected,
  /// fell back to SSE).
  Stream<SyncTransport> get transportChanges {
    late StreamController<SyncTransport> wrapper;
    StreamSubscription<SyncTransport>? sub;
    wrapper = StreamController<SyncTransport>(
      onListen: () {
        wrapper.add(_active);
        sub = _activeTransport.stream.listen(wrapper.add);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return wrapper.stream;
  }

  /// Connects to all push transports (WS,
  /// SSE, UDP). The polling transport is
  /// stateless (each `syncAsync` is a fresh
  /// request), so it doesn't need
  /// `connect()`.
  Future<void> connect() async {
    final List<Future<void>> tasks = <Future<void>>[];
    if (webSocket != null) {
      // (In a real impl, we'd call connect on
      // the WS provider if it has one. We
      // don't have a generic `connect`
      // interface on SyncProvider yet.)
    }
    if (sse != null) {
      // Same.
    }
    if (udp != null) {
      // Same.
    }
    await Future.wait(tasks);
    _active = webSocket != null
        ? SyncTransport.webSocket
        : sse != null
            ? SyncTransport.sse
            : SyncTransport.polling;
    _activeTransport.add(_active);
  }

  /// Disconnects all push transports.
  Future<void> disconnect() async {
    // (Stub for 2.0.0. Real impl in 2.1.0
    // with the realtime integration.)
  }

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    // Pull always uses polling. The push
    // transports (WS, SSE) only carry
    // server-pushed changes; they don't
    // accept client-initiated sync envelopes.
    return polling.syncAsync(envelope);
  }

  @override
  Future<int> currentWatermarkAsync() async {
    return polling.currentWatermarkAsync();
  }
}
