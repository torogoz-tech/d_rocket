//: WebSocket client. Full-duplex
// real-time channel over TCP. The user uses
// `IOWebSocketClient` on the Dart VM (server-side
// + tests) and Flutter (mobile). On the web, the
// `dart:io` WebSocket is not available — for
// that the user wraps `package:web_socket_channel`
// (the interface here is the same).
//
// The pattern:
//
// ```dart
// final client = IOWebSocketClient;
// await client.connect(Uri.parse('ws://localhost:8080/ws'));
// client.messages.listen((msg) {
// if (msg.isText) print('Got: ${msg.text}');
// });
// await client.send(WebSocketMessage.text('hello'));
// await client.close;
// ```

// `dart:io` is not available on the web. Use a
// conditional export so the native `io_websocket_client.dart`
// (backed by `dart:io`) is used on Dart VM and Flutter
// mobile/desktop, while `web_websocket_client.dart`
// (a stub that throws `UnsupportedError`) is used on
// the web. To wire a real web transport, replace the
// stub with a `package:web_socket_channel` adapter.
export 'io_websocket_client.dart'
    if (dart.library.js_interop) 'web_websocket_client.dart';
export 'websocket_connection.dart';
export 'websocket_message.dart';
export 'websocket_message_type.dart';
export 'websocket_reconnector.dart';
