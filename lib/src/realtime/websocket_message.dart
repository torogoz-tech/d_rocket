import 'websocket_message_type.dart';

/// One WebSocket frame: either a text string or
/// a binary blob. Use [WebSocketMessage.text] and
/// [WebSocketMessage.binary] to construct one.
class WebSocketMessage {
  const WebSocketMessage._text(this.text)
      : type = WebSocketMessageType.text,
        binary = null;

  const WebSocketMessage._binary(this.binary)
      : type = WebSocketMessageType.binary,
        text = null;

  factory WebSocketMessage.text(String text) => WebSocketMessage._text(text);
  factory WebSocketMessage.binary(List<int> bytes) =>
      WebSocketMessage._binary(List<int>.unmodifiable(bytes));

  final WebSocketMessageType type;
  final String? text;
  final List<int>? binary;

  bool get isText => type == WebSocketMessageType.text;
  bool get isBinary => type == WebSocketMessageType.binary;

  @override
  String toString() => isText
      ? 'WebSocketMessage.text($text)'
      : 'WebSocketMessage.binary(${binary!.length} bytes)';
}
