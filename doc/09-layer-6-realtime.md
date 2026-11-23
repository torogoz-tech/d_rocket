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
`WebSocketReconnector` wrapper handles initial and
mid-session reconnects with exponential backoff until
`maxAttempts` is reached or the owner calls `stop()`.

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
- [Web target — `IOWebSocketClient` browser stub](#web-target--iowebsocketclient-browser-stub)
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

The low-level `WebSocketReconnector` also accepts an optional
`heartbeatInterval`. When set, it sends an application-level ping frame (or
the supplied `heartbeatMessage`) while connected. The timer is cancelled on
disconnect and `stop()`. This is separate from a WebSocket protocol ping so
servers that use JSON application messages can observe and acknowledge it.

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

## Robust `SseReconnector`

Since 2.2.2, the runtime also exposes `SseReconnector` for consumers that need
direct control over an SSE connection. `headersProvider` runs before every
attempt and `onUnauthorized` can refresh the session when the server returns
`401`:

```dart
final SseReconnector stream = SseReconnector(
  factory: HttpSseClient.new,
  url: Uri.parse('https://api.example.com/events'),
  headersProvider: () async => <String, String>{
    'Authorization': 'Bearer ${await session.accessToken()}',
  },
  onUnauthorized: () async => session.refresh(),
  inactivityTimeout: const Duration(minutes: 2),
  manualAcknowledge: true,
);
```

Observe lifecycle through `states` (`connecting`, `connected`, `retrying`,
`stopped` and `failed`). HTTP errors are exposed as `SseHttpException` with
their `statusCode`; `403` is terminal and does not create infinite retries.

The cursor can be acknowledged after persisting the event:

```dart
stream.events.listen((event) async {
  await repository.save(event.data);
  stream.acknowledge(event);
});
```

`clearLastEventId()` clears the cursor. `stop()` cancels retries, subscriptions
and transport, while a later `start()` creates a new generation that ignores
late events from the previous connection. `dispose()` also closes public
streams. The `inactivityTimeout` timer considers both events and SSE comments
used as heartbeats.

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
  HttpSseClient({
    Map<String, String> defaultHeaders = const {},
    List<SseInterceptor> interceptors = const [],
    Duration? connectTimeout = const Duration(seconds: 30),
    bool followRedirects = true,
    bool validateContentType = true,
  });

  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  });
  Future<void> close();
}
```

The normal constructor creates and owns its HTTP
transport. `defaultHeaders`, `interceptors`, the
initial response timeout, redirect policy and
`text/event-stream` validation are configured on
`HttpSseClient` itself. An optional `http.Client`
can still be injected for tests or specialized
transports; injected clients remain caller-owned unless
`ownsHttpClient: true` is supplied. Calling `close()`
twice is safe and closes an owned pending or active
transport.

## Shared transport policies

`TransportPolicy` can be shared by generated REST
clients, `HttpSseClient` and `TransportStreamingClient`.
The request callback receives the final URI for each
attempt, so an application can add a current token or a
new DPoP proof. The response callback can request a
bounded repeat:

```dart
final policy = TransportPolicy(
  onRequest: (context) async => context.copyWith(
    headers: <String, String>{
      ...context.headers,
      'Authorization': 'Bearer ${await session.accessToken()}',
    },
  ),
  onResponse: (context) => context.statusCode == 401
      ? const TransportResponseDecision.retry()
      : const TransportResponseDecision.accept(),
);

final downloads = TransportStreamingClient(policy: policy);
```

Streaming downloads follow redirects through the policy
pipeline. When the origin changes,
`TransportRequestContext.forRedirect` removes credential
headers before the next request; the policy can then add
credentials suitable for the redirected URI.

## `WebSocketReconnector`

Auto-reconnecting wrapper. Wraps any
`WebSocketConnection` factory and retries the
initial connection and later disconnects with
exponential backoff.

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

### Constructor parameters

| Parameter | Default | Purpose |
|---|---|---|
| `factory` | (required) | `WebSocketConnection Function()` — creates a new client on each (re)connect. |
| `url` | (required) | The WebSocket endpoint. |
| `headers` | `null` | Optional upgrade headers (e.g. `Authorization`). |
| `initialBackoff` | `1s` | Base backoff; doubles on every retry (1s, 2s, 4s, 8s, 16s). |
| `maxAttempts` | `5` | Maximum connect attempts before re-throwing the last error. |

### Wiring into `IOWebSocketClient`

`WebSocketReconnector` is the standard wrapper
used by codegen-emitted `_$<ClassName>` clients
when the user declares
`reconnectBackoffSeconds` on `@WebSocketClient`:

```dart
// Manual wiring (when not using codegen):
final reconnector = WebSocketReconnector(
  factory: () => IOWebSocketClient(),
  url: Uri.parse('wss://api.example.com/realtime'),
  headers: {'Authorization': 'Bearer $token'},
  initialBackoff: const Duration(seconds: 1),
  maxAttempts: 5,
);
await reconnector.start();

// Forward messages:
await for (final msg in reconnector.messages) {
  print('got: $msg');
}
```

| Member | Purpose |
|---|---|
| `client` | The underlying `WebSocketConnection`. `null` before `start` and during reconnects. |
| `messages` | Broadcast `Stream<WebSocketMessage>` forwarded from the underlying client and preserved across reconnects. |
| `states` / `state` | Observable `connecting`, `connected`, `retrying`, `stopped` and `failed` lifecycle. |
| `headersProvider` | Async callback evaluated before every connection and retry. Use it for rotating tokens. |
| `statusCode` | HTTP status exposed by transports that can report the WebSocket upgrade response. |
| `onUnauthorized` | One-shot 401 recovery callback. Return `true` after refreshing auth; 403 is terminal. |
| `inactivityTimeout` | Reconnects after no inbound traffic. Heartbeat sends reset this timer. |
| `lastError` / `lastStackTrace` | Last connection failure retained for UI, logs or diagnostics. |
| `lastCloseCode` / `lastCloseReason` | Optional peer close details from transports that expose them. |
| `start()` | Tries `maxAttempts` times with exponential backoff; re-throws on exhaustion. |
| `stop()` / `dispose()` | Cancel retries, timers and subscriptions; close the connection. `start()` can be called again after `stop()`. |

### Behaviour and limitations

The backoff is exponential:
`1s, 2s, 4s, 8s, 16s`. After `maxAttempts` the
last error is re-thrown.

Mid-session reconnects are automatic and use the same bounded exponential
backoff. A successful connection resets the retry counter. Events from an old
connection are ignored after `stop()` or a later `start()`.

```dart
final sub = reconnector.client!.messages.listen(
  (msg) => handle(msg),
  onDone: () async {
    await reconnector.stop();
    await reconnector.start();   // re-arm on disconnect
  },
);
```

For exponential-backoff-after-disconnect
(separate from the initial connect retries), the
user wraps the `onDone` handler in their own
delay loop.

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

## Web target — `IOWebSocketClient` browser stub

`d_rocket` ships a conditional-import stub at
`lib/src/realtime/web_websocket_client.dart`
that exposes the same public class
(`IOWebSocketClient`) but is selected on the web
build instead of the `dart:io` implementation.
On the web, `dart:io` is not available, so every
operation throws `UnsupportedError`:

```dart
UnsupportedError: IOWebSocketClient is not available on the web.
Use a `package:web_socket_channel`-backed `WebSocketConnection` adapter.
```

| Operation | Web behaviour |
|---|---|
| `connect(url, headers: ...)` | Throws `UnsupportedError`. |
| `send(message)` | Throws `UnsupportedError`. |
| `close({code, reason})` | Throws `UnsupportedError`. |
| `messages` (getter) | Throws `UnsupportedError`. |
| `errors` (getter) | Throws `UnsupportedError`. |
| `closed` (getter) | Throws `UnsupportedError`. |
| `isConnected` (getter) | Always returns `false`. |

The public interface is intentionally identical
to the `dart:io` `IOWebSocketClient` so the call
site does not change. To enable real WebSocket
support on the web, drop in
`package:web_socket_channel` behind a
`WebSocketConnection` adapter:

```dart
class ChannelWebSocketConnection implements WebSocketConnection {
  // wraps `IOWebSocketChannel` from package:web_socket_channel
}
```

Replace the stub via a custom `build.yaml` /
conditional-import or by overriding the export
in your fork. Until then, generated clients
that target `@WebSocketClient` on the web will
throw on connect.

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

### `IOWebSocketClient` (web stub)

Conditional-import browser stub that throws
`UnsupportedError`. See [Web target](#web-target--iowebsocketclient-browser-stub).

### `SseConnection` / `HttpSseClient`

Abstract transport / `package:http` implementation.
See [SseConnection](#sseconnection-and-httpsseclient)
above.

### `WebSocketReconnector`

Auto-reconnecting wrapper for the initial
connection. See [WebSocketReconnector](#websocketreconnector)
above. Includes constructor parameters, `client`
/ `messages` / `start` / `stop` members, and the
mid-session-reconnect pattern.

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
