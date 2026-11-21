/// Lifecycle states emitted by [WebSocketReconnector].
enum WebSocketReconnectorState {
  /// A connection attempt is being made.
  connecting,

  /// A connection is open and receiving messages.
  connected,

  /// The connection was lost and a retry is scheduled.
  retrying,

  /// The reconnector was stopped by its owner.
  stopped,

  /// The reconnector cannot continue after a terminal failure.
  failed,
}
