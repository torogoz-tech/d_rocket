/// 2.0.0 — sync transports.
///
/// A [SyncTransport] is the **medium** that
/// carries sync data. d_rocket 2.0.0 supports
/// 4 transports:
///
/// | Transport | Direction | Latency | Use case |
/// |---|---|---|---|
/// | `polling` | client → server (pull) | high (5-60s) | The default. Always works. No persistent connection. |
/// | `webSocket` | bidirectional | low (<100ms) | Real-time sync, server can push changes. |
/// | `sse` | server → client (push only) | medium (1-5s) | Server pushes, client pulls occasionally. Good when WS is not available. |
/// | `udp` | bidirectional | very low (<10ms) | IoT, gaming, real-time multiplayer. Lossy — only useful for ephemeral state. |
///
/// Use [MultiTransportSyncProvider] to combine
/// multiple transports — e.g. WebSocket as
/// primary, SSE as fallback, polling as
/// last-resort. The combination picks the best
/// available transport at runtime.
library;

/// The kind of transport a [SyncProvider] uses.
enum SyncTransport {
  /// HTTP polling. The client makes a request
  /// every N seconds; the server responds
  /// with the diff since the last watermark.
  /// The default — always works.
  polling,

  /// WebSocket. The client opens a persistent
  /// bidirectional connection; the server can
  /// push changes at any time. Lower latency
  /// but requires the server to support WS.
  webSocket,

  /// Server-Sent Events. The server pushes
  /// changes over a long-lived HTTP response;
  /// the client can only receive (not send)
  /// over this transport. Usually paired with
  /// polling for the client's outgoing
  /// changes.
  sse,

  /// UDP. Bidirectional but unreliable.
  /// Useful for real-time state (positions,
  /// scores) where packet loss is acceptable.
  /// Not for general sync — use only for
  /// ephemeral state.
  udp,
}
