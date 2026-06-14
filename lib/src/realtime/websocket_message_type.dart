/// The type of a [WebSocketMessage] frame.
enum WebSocketMessageType {
  /// A text frame (UTF-8 string).
  text,

  /// A binary frame (`List<int>`).
  binary,
}
