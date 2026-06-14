//: annotations for codegen-time
// discovery of WebSocket + SSE clients.
//
// Usage:
//
// ```dart
// @WebSocketClient(url: 'wss://api.example.com/ws')
// abstract class MyWsClient { ... }
//
// @SseClient(url: 'https://api.example.com/events')
// abstract class MySseClient { ... }
// ```
//
// The `d_rocket_builder:realtime` generator
// emits a `_$<ClassName>` that extends
// `IOWebSocketClient` / `HttpSseClient` and a
// `register<X>WebSocketClient` /
// `register<X>SseClient` factory for the
// central `initializeD`.

///: marks an abstract class as a
/// [IOWebSocketClient] (the user defines the URL +
/// optionally headers, the builder emits the
/// connection + reconnect glue).
class WebSocketClient {
  ///: the URL to connect to.
  final String url;

  ///: default headers (e.g. auth).
  final Map<String, String> headers;

  ///: the typed-events the user
  /// wants to send. The builder generates
  /// `send<TExtendsEvent>(name, payload)` for
  /// each one.
  final List<String> sendEventNames;

  ///: the typed-events the user
  /// wants to receive. The builder generates
  /// `Stream<TExtendsEvent> on<TEvent>(name)`.
  final List<String> receiveEventNames;

  ///: default reconnect backoff
  /// (in seconds). Used by the generated
  /// [WebSocketReconnector] wrapper.
  final int reconnectBackoffSeconds;

  const WebSocketClient({
    required this.url,
    this.headers = const <String, String>{},
    this.sendEventNames = const <String>[],
    this.receiveEventNames = const <String>[],
    this.reconnectBackoffSeconds = 1,
  });
}

///: marks an abstract class as an
/// [HttpSseClient] (the user defines the URL +
/// optionally lastEventId, the builder emits
/// the connect + lastEventId logic).
class SseClient {
  ///: the URL to connect to.
  final String url;

  ///: default headers (e.g. auth).
  final Map<String, String> headers;

  ///: the typed-events the user
  /// wants to receive. The builder generates
  /// `Stream<TExtendsEvent> on<TEvent>(name)`.
  final List<String> receiveEventNames;

  ///: default retry hint (in
  /// milliseconds). Used by the server (we just
  /// forward it back via `Last-Event-ID`).
  final int retryHintMs;

  const SseClient({
    required this.url,
    this.headers = const <String, String>{},
    this.receiveEventNames = const <String>[],
    this.retryHintMs = 3000,
  });
}
