# Layer 6 — Realtime

`@WebSocketClient` and `@SseClient` mark abstract
classes as typed realtime clients. The codegen
(`d_rocket_builder`) reads the annotation and emits
a private `_$<ClassName>` that extends
`IOWebSocketClient` (for WebSocket) or
`HttpSseClient` (for SSE). The generated class
exposes typed `send<TExtendsEvent>(name, payload)`
and `Stream<TExtendsEvent> on<TEvent>(name)` methods
for every event name the user declared.

The realtime layer reuses the serializer registry
from Layer 1 for inbound / outbound payloads. The
`WebSocketReconnector` wrapper handles the initial
connect with exponential backoff; mid-session
reconnects are not automatic (the user's `onDone`
handler re-arms the wrapper).

This is the **realtime layer**. It is the most
common consumer of a realtime stream in the
`SyncProvider.pull` method (Layer 5).

---

## Table of contents

- [Defining a client](#defining-a-client)
- [`@WebSocketClient` parameters](#websocketclient-parameters)
- [`@SseClient` parameters](#sseclient-parameters)
- [Generated event API](#generated-event-api)
- [`WebSocketConnection` and `IOWebSocketClient`](#websocketconnection-and-iowebsocketclient)
- [`SseConnection` and `HttpSseClient`](#sseconnection-and-httpsseclient)
- [`WebSocketReconnector`](#websocketreconnector)
- [`WebSocketMessage` and `SseEvent`](#websocketmessage-and-sseevent)
- [Use in a `SyncProvider.pull` (Layer 5)](#use-in-a-syncproviderpull)
- [API reference](#api-reference)

---

## Defining a client

```dart
import 'package:d_rocket/d_rocket.dart';

@WebSocketClient(
  url: 'wss://api.example.com/realtime',
  headers: {'Authorization': 'Bearer $token'},
  sendEventNames: ['chat', 'typing'],
  receiveEventNames: ['message', 'user_joined', 'user_left'],
  reconnectBackoffSeconds: 1,
)
abstract class ChatClient {}

// Or, for SSE:
@SseClient(
  url: 'https://api.example.com/events',
  receiveEventNames: ['metric', 'alert'],
)
abstract class MetricsClient {}
```

The abstract class is a marker — the codegen emits
the implementation. The generated class is named
`_<ClassName>` (private). It's wired into the
central `initializeD()` via a `register<X>Client`
call.

A `ChatClient` is constructed by the codegen
emitter; the user obtains a fully-wired instance
via the central registry.

## `@WebSocketClient` parameters

```dart
const WebSocketClient({
  required this.url,
  this.headers = const <String, String>{},
  this.sendEventNames = const <String>[],
  this.receiveEventNames = const <String>[],
  this.reconnectBackoffSeconds = 1,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `url` | (required) | The `wss://` URL to connect to. |
| `headers` | `{}` | Default headers (sent on the `Connection: Upgrade` request, e.g. for auth). |
| `sendEventNames` | `[]` | The typed-events the user wants to send. The codegen generates `send<TExtendsEvent>(name, payload)` for each. |
| `receiveEventNames` | `[]` | The typed-events the user wants to receive. The codegen generates `Stream<TExtendsEvent> on<TEvent>(name)` for each. |
| `reconnectBackoffSeconds` | `1` | Initial backoff for the `WebSocketReconnector` wrapper. The actual delay doubles on every attempt (1s, 2s, 4s, 8s, 16s) up to `maxAttempts` (default 5). |

## `@SseClient` parameters

```dart
const SseClient({
  required this.url,
  this.headers = const <String, String>{},
  this.receiveEventNames = const <String>[],
  this.retryHintMs = 3000,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `url` | (required) | The `https://` URL to connect to. |
| `headers` | `{}` | Default headers (e.g. auth). |
| `receiveEventNames` | `[]` | The typed-events the user wants to receive. |
| `retryHintMs` | `3000` | Default retry hint (in milliseconds). The server sees this in the `retry: <ms>` line; the client just forwards it back via `Last-Event-ID`. |

SSE is one-way (server → client). The `@SseClient`
annotation has no `sendEventNames` (the client
cannot send events over SSE — it would use a
`@WebSocketClient` for that).

## Generated event API

The codegen reads the user's `@Serializable` classes
that extend a marker (e.g. `class ChatEvent` or
`class MessageEvent` for the `message` event name)
and emits:

```dart
class _$ChatClient extends IOWebSocketClient {
  // Per receiveEventName:
  Stream<MessageEvent> onMessage() {
    return messages
        .where((m) => m.isText)
        .map((m) => Serializer.fromDynamic<MessageEvent>(jsonDecode(m.text!)))
        .where((m) => /* discriminator matches 'message' */)
        .asBroadcastStream();
  }
  // ...

  // Per sendEventName:
  Future<void> sendChat(ChatEvent payload) async {
    await send(WebSocketMessage.text(jsonEncode({
      'event': 'chat',
      'payload': Serializer.toJson(payload),
    })));
  }
}
```

The exact shape of the generated `send<Name>` /
`on<Name>` methods is the codegen's choice. The
framework guarantees:

- Every `receiveEventNames` entry has a
  `Stream<T> on<Name>()` method that filters
  inbound messages by event name and
  deserializes through the `Serializer` registry.
- Every `sendEventNames` entry has a
  `Future<void> send<Name>(T payload)` method
  that serializes through the `Serializer`
  registry and sends the JSON envelope.

## `WebSocketConnection` and `IOWebSocketClient`

`WebSocketConnection` is the abstract contract:

```dart
abstract class WebSocketConnection {
  Stream<WebSocketMessage> get messages;
  Future<void> connect(Uri url, {Map<String, String>? headers});
  Future<void> send(WebSocketMessage message);
  Future<void> close({int? code, String? reason});
  bool get isConnected;
}
```

`IOWebSocketClient` is the `dart:io`-backed
implementation. Works on the Dart VM (server-side +
tests) and Flutter (iOS / Android / desktop). Does
NOT work on the web (use a `ChannelWebSocketConnection`
that wraps `package:web_socket_channel`).

```dart
class IOWebSocketClient implements WebSocketConnection {
  IOWebSocketClient();

  Stream<WebSocketMessage> get messages;     // broadcast
  Stream<Object> get errors;                  // broadcast (NEW)
  Future<void> get closed;                    // completes on close

  Future<void> connect(Uri url, {Map<String, String>? headers});
  Future<void> send(WebSocketMessage message);
  Future<void> close({int? code, String? reason});
  bool get isConnected;
}
```

`errors` is a separate broadcast stream (the
`messages` stream is silent on errors — subscribe
to `errors` to observe them). `closed` is a
`Future<void>` that completes when the connection
is closed.

## `SseConnection` and `HttpSseClient`

`SseConnection` is the abstract contract:

```dart
abstract class SseConnection {
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  });
  Future<void> close();
}
```

`HttpSseClient` is the `package:http`-backed
implementation. Works on the Dart VM, Flutter, and
(eventually) the web.

The `connect` call returns a `Stream<SseEvent>` —
when the server closes the connection, the stream
ends. The `lastEventId` is sent as the
`Last-Event-ID` header so the server can resume
from where the client left off.

```dart
class HttpSseClient implements SseConnection {
  HttpSseClient({http.Client? httpClient});

  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  });
  Future<void> close();
}
```

The `httpClient` is DI-friendly (default is a
fresh `http.Client` per instance). For tests,
inject a `MockClient` (via
`http.Client` constructor) or a real
`http.Client`.

## `WebSocketReconnector`

Auto-reconnecting wrapper. Wraps any
`WebSocketConnection` factory and retries the
initial `start()` call with exponential backoff
when it fails.

```dart
class WebSocketReconnector {
  WebSocketReconnector({
    required this.factory,
    required this.url,
    this.headers,
    Duration initialBackoff = const Duration(seconds: 1),
    int maxAttempts = 5,
  });

  Stream<WebSocketMessage> get messages;
  Future<void> start();
  Future<void> stop();
}
```

The backoff is exponential:
`1s, 2s, 4s, 8s, 16s`. After `maxAttempts` the
last error is re-thrown.

**Mid-session reconnects are NOT automatic** — the
user wires their own `onDone` handler to re-arm
the reconnector when the underlying connection
ends. This is intentional: a long-lived
realtime stream's reconnect policy is a
user-facing decision (per-screen, per-event-type,
etc.), and the framework doesn't presume.

## `WebSocketMessage` and `SseEvent`

### `WebSocketMessage`

```dart
class WebSocketMessage {
  factory WebSocketMessage.text(String text);
  factory WebSocketMessage.binary(List<int> bytes);

  final WebSocketMessageType type;   // text or binary
  final String? text;
  final List<int>? binary;
  bool get isText;
  bool get isBinary;
}
```

Construct via the named factories. The type
discriminates text vs binary. The unused field
is `null`.

### `SseEvent`

```dart
class SseEvent {
  const SseEvent({
    required this.data,        // joined with \n
    this.event,
    this.id,
    this.retry,
  });

  final String data;           // event payload
  final String? event;         // event name (defaults to 'message')
  final String? id;            // last-event-id
  final Duration? retry;       // retry hint
}
```

Multiple `data:` lines in the wire format are
joined with `\n` and exposed as `data`. The
`event` field defaults to `'message'` if the
server didn't specify one.

## Use in a `SyncProvider.pull` (Layer 5)

The most common use of the realtime layer is as
the pull source for Layer 5 (sync). The pattern:

```dart
class MyBackendSyncProvider implements SyncProvider {
  MyBackendSyncProvider(this.realtime);

  final ChatClient realtime;  // the codegen-emitted client

  @override
  Stream<SyncChange> pull() {
    // Server pushes each change as a SyncOp over the
    // realtime channel. The sync runtime consumes
    // this stream and applies each op to the local DB.
    return realtime.onSyncOps();
  }
}
```

The advantage over a polling loop is that the
server pushes changes immediately, so the local DB
is up-to-the-second. The disadvantage is that the
WebSocket is a fragile connection (handled by
`WebSocketReconnector`) and the server needs to
maintain it.

For most apps, a hybrid is best: a low-rate polling
loop as a fallback (via `PeriodicSyncTrigger` from
Layer 5), with a WebSocket upgrade when
connectivity is good. The `WebSocketReconnector` is
configured to give up after `maxAttempts` (default
5), and the user's `onDone` handler falls back to
polling.

## API reference

### `@WebSocketClient(url, headers, sendEventNames, receiveEventNames, reconnectBackoffSeconds)`

Class annotation. See parameters above.

### `@SseClient(url, headers, receiveEventNames, retryHintMs)`

Class annotation. See parameters above.

### `WebSocketConnection` / `IOWebSocketClient`

Abstract transport / `dart:io` implementation. See
[WebSocketConnection](#websocketconnection-and-iowebsocketclient)
above.

### `SseConnection` / `HttpSseClient`

Abstract transport / `package:http` implementation.
See [SseConnection](#sseconnection-and-httpsseclient)
above.

### `WebSocketReconnector`

Auto-reconnecting wrapper for the initial
connection. See [WebSocketReconnector](#websocketreconnector)
above.

### `WebSocketMessage` / `WebSocketMessageType`

Message envelope. `WebSocketMessageType` is an
enum with 2 values: `text`, `binary`.

### `SseEvent`

SSE event envelope. `data` (joined), `event`
(name), `id` (resume), `retry` (hint).

### `register<X>Client` (codegen-emitted)

Every `@WebSocketClient` / `@SseClient` class
registers itself in the central
`initializeD()` via a `register<X>Client` call.
The user obtains a fully-wired instance via the
generated accessor.
