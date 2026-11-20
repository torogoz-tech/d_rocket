/// Lifecycle states exposed by [SseReconnector].
enum SseReconnectorState {
  connecting,
  connected,
  retrying,
  stopped,
  failed,
}
