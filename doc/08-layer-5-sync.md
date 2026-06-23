# Layer 5 — Sync (offline-first ↔ cloud)

The sync layer is the bridge between a local-first
`DbContext` and a remote backend. Local mutations
accumulate in a `pendingSyncChanges` queue; a `syncAsync`
call drains the queue to a `SyncProvider` and applies the
remote response locally with last-write-wins conflict
resolution (or a user-supplied strategy).

This is the **offline-first layer**. Reads come from the
local database (Layer 4). Writes queue into `pendingSyncChanges`
on every `saveChangesAsync`; the orchestrator flushes them
in the background. The default trigger is the user wiring
`PeriodicSyncTrigger` or `SignalSyncTrigger` to `startSyncTriggers`.

---

## Table of contents

- [The offline-first model](#the-offline-first-model)
- [`SyncProvider` — the contract](#syncprovider)
- [`SyncEnvelope` and `SyncChange`](#syncenvelope-and-syncchange)
- [The orchestrator — `DbContext.syncAsync`](#the-orchestrator)
- [Conflict resolution](#conflict-resolution)
- [Triggers — `SyncTrigger`](#triggers)
- [State — `SyncStateStore`](#state)
- [Implementations — `RestSyncProvider` and friends](#implementations)
- [`SyncTransport` and multi-transport providers](#synctransport-and-multi-transport-providers)
- [Retry policies — extended set](#retry-policies--extended-set)
- [`SyncStateStore` implementations](#syncstatestore-implementations)
- [`SyncQueueStore`](#syncqueuestore)
- [`SyncProgress` and `SyncMetrics` (observability)](#syncprogress-and-syncmetrics-observability)
- [`SyncFilter` (selective sync)](#syncfilter-selective-sync)
- [`SyncSchema` (versioning)](#syncschema-versioning)
- [`AuthRefreshSync` (auto-refresh on 401)](#authrefreshsync-auto-refresh-on-401)
- [`ConnectivityProvider` (online / offline)](#connectivityprovider-online--offline)
- [`MultiTenantSync` (per-tenant isolation)](#multitenantsync-per-tenant-isolation)
- [`SyncPriority` and `VectorClock`](#syncpriority-and-vectorclock)
- [`RestSyncException`](#restsyncexception)
- [`FileSync` (binary blobs)](#filesync-binary-blobs)
- [Common pitfalls](#common-pitfalls)
- [API reference](#api-reference)

---

## The offline-first model

```
                  ┌────────────────────────────────────────────┐
                  │                                            │
                  │            user actions                    │
                  │                                            │
                  └────────────────┬───────────────────────────┘
                               │
                               ▼
              ┌────────────────────────────────────────────┐
              │  DbSet<T>.add() / markModified() / remove()  │
              │  + ChangeTracker + pendingSyncChanges      │
              └────────┬───────────────────────┬────────────┘
                       │                       │
                       │  reads                │  writes
                       │  (sync)               │  (async)
                       ▼                       ▼
       ┌───────────────────────┐   ┌───────────────────────────┐
       │     local SQLite      │   │  pendingSyncChanges queue  │
       │     (Layer 4)         │   │   (in-memory, in ctx)      │
       └───────────────────────┘   └───────────┬───────────────┘
                                              │ ctx.syncAsync(provider)
                                              ▼
                                  ┌───────────────────────────┐
                                  │   SyncProvider            │
                                  │  (RestSyncProvider, etc.) │
                                  └───────────┬───────────────┘
                                              │
                                              ▼
                                  ┌───────────────────────────┐
                                  │   remote server           │
                                  └───────────────────────────┘
```

The `pendingSyncChanges` queue is **persisted to
SQLite** (since 1.1.1) in a `d_rocket_sync_queue`
table. The INSERT happens in the same transaction
as the data write (inside `saveChanges` /
`saveChangesAsync`), so a crash between the
write and the next `syncAsync` does not lose
queued changes. A failed sync keeps the queue
intact (the next `syncAsync` retries the same
changes). The previous in-memory queue is
deprecated; consumers that referenced it via
`ctx.pendingSyncChanges` continue to work (the
getter is now backed by the on-disk table).

## `SyncProvider` — the contract

The user implements a `SyncProvider` to talk to their
backend (REST, Firebase, Supabase, custom). The
contract is intentionally small — two methods:

```dart
abstract class SyncProvider {
  /// Receives the local envelope and returns the
  /// remote envelope (the changes that have happened
  /// on the server since `envelope.since`).
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope);

  /// Returns the current server-side watermark
  /// (e.g. the latest `version` of any change).
  /// The user can use this to bootstrap the local
  /// watermark.
  Future<int> currentWatermarkAsync();
}
```

That's it. The user (or one of the bundled
implementations) handles the wire format. The
`SyncProvider` does NOT need to expose `push`,
`pull`, or `resolveConflict` — those concerns are
baked into the `syncAsync` orchestration in
`DbContext`.

### Bundled implementations

| Class | Purpose |
|---|---|
| `RestSyncProvider` | HTTP + JSON over the high-level `HttpClient` (Layer 2). POSTs the envelope to `$baseUrl/sync`; GETs the watermark from `$baseUrl/sync/watermark`. |
| `InMemorySyncProvider` | No I/O. For tests. |

### `RestSyncProvider`

```dart
class RestSyncProvider implements SyncProvider {
  RestSyncProvider({
    required this.baseUrl,
    HttpClient? client,         // defaults to HttpPackageClient()
    Map<String, String>? headers,
    Duration? timeout,
  });
}
```

`baseUrl` is the API root (e.g.
`https://api.example.com`). The provider appends
`/sync` and `/sync/watermark` for the two endpoints.

`client` is the Layer-2 `HttpClient` to use. Pass
any composed client (e.g.
`RetryingHttpClient(inner: HttpPackageClient())`)
and the provider inherits every Layer-2 feature
(interceptors, retry, circuit breaker).

`headers` are extra HTTP headers (e.g. for auth:
`'Authorization': 'Bearer $token'`).

## `SyncEnvelope` and `SyncChange`

### `SyncEnvelope`

A batch of `SyncChange`s.

```dart
class SyncEnvelope {
  const SyncEnvelope({
    required this.clientId,
    required this.since,
    required this.changes,
  });

  final String clientId;             // identifies the device
  final int since;                    // last watermark synced
  final List<SyncChange> changes;     // batch of changes

  Map<String, Object?> toJson();
  static SyncEnvelope fromJson(Map<String, Object?> json);
}
```

`clientId` is a unique id assigned to the device
on first launch (e.g. a UUID). The server uses it
to echo back changes for OTHER clients to receive.

`since` is the last watermark the client has seen.
The server returns changes that happened on the
server AFTER `since`. The client then advances the
watermark to the new value.

### `SyncChange`

One row in a `SyncEnvelope`.

```dart
class SyncChange {
  const SyncChange({
    required this.tableName,
    required this.pk,
    required this.type,
    required this.payload,
    required this.version,
  });

  final String tableName;                       // local table name
  final String pk;                              // PK value (as String)
  final SyncChangeType type;                    // upsert or delete
  final Map<String, Object?>? payload;          // row data, or null for delete
  final int version;                            // monotonic (e.g. ms timestamp)
}
```

`version` is a monotonically increasing number
(typically a millisecond timestamp) used for
last-write-wins conflict resolution. The server
assigns the version; the client just trusts it.

### `SyncChangeType`

```dart
enum SyncChangeType {
  upsert,    // insert or update a row
  delete,    // delete a row
}
```

`upsert` covers both insert and update. The
`payload` is the full row data; the client decides
whether to insert or update by checking if the row
already exists locally.

## The orchestrator

`DbContext.syncAsync(provider, ...)` is the
orchestrator. It runs a 3-step round-trip:

1. **Push.** Drain the `d_rocket_sync_queue` table
   (populated by `saveChanges` /
   `saveChangesAsync` after a successful commit) into
   a `SyncEnvelope` with the current
   `_clientWatermark` as `since`. The DELETE that
   removes the queue rows happens in the same
   transaction as the new `clientWatermark` write.
2. **Pull.** Call `provider.syncAsync(envelope)`.
   The provider returns a `SyncEnvelope` with
   changes that happened on the server since
   `envelope.since`.
3. **Apply.** For each `SyncChange` in the remote
   response, apply locally with last-write-wins
   conflict resolution.
4. **Persist.** If `stateStore` is provided, save
   the new watermark.
5. **Retry.** If `retryPolicy` is provided AND the
   round-trip fails, sleep + retry (per the
   policy).

The `pendingSyncChanges` queue is cleared only on
a successful sync (so a failed sync retries on the
next call).

```dart
Future<List<SyncChange>> syncAsync(
  SyncProvider provider, {
  String? clientId,           // legacy; prefer bootstrapSync()
  SyncStateStore? stateStore,
  RetryPolicy? retryPolicy,
});
```

Returns the list of remote changes that were
applied. Throws `StateError` if neither the
parameter nor `bootstrapSync()` provided a
`clientId`.

## Conflict resolution

The conflict-resolution contract is exposed in
two forms: a bare `ConflictResolver` typedef
(legacy) and a typed sealed `ConflictPolicy`
hierarchy (preferred).

### `ConflictResolver` (typedef, legacy)

```dart
typedef ConflictResolver = Map<String, Object?> Function(
  Map<String, Object?> localRow,
  Map<String, Object?> remotePayload,
);
```

The resolver receives the current local row and the
remote payload, and returns the merged row to apply.

### `ConflictPolicy` (sealed, preferred)

`ConflictPolicy` is the typed, sealed API. The
hierarchy has four concrete subclasses:

| Subclass | Constant | Behaviour |
|---|---|---|
| `LwwConflictPolicy` | `ConflictPolicy.lww` / `ConflictPolicy.serverWins` | Server wins. Merged row = `{...localRow, ...remotePayload}`. |
| `ClientWinsConflictPolicy` | `ConflictPolicy.clientWins` | Local wins. Merged row = `{...remotePayload, ...localRow}`. |
| `CustomConflictPolicy` | `ConflictPolicy.custom(resolver)` | User-provided merge callback. |
| (sealed) | — | Sealed: new variants are extension points, not open-ended subtypes. |

The default behaviour of `DbContext.syncAsync`
remains LWW (`ConflictPolicy.lww`):

```dart
final serverWins = ConflictPolicy.lww;
final clientWins = ConflictPolicy.clientWins;
final columnAware = ConflictPolicy.custom(
  MergeStrategies.preferLocalColumns(<String>['updated_by']),
);
```

### `MergeStrategies` (pre-built merge helpers)

Three helpers plug into `ConflictPolicy.custom`
for common cases:

```dart
class MergeStrategies {
  static ConflictResolver preferLocalColumns(List<String> localColumns);
  static ConflictResolver preferRemoteColumns(List<String> remoteColumns);
  static ConflictResolver maxOf(List<String> counterColumns);
}
```

| Helper | Use case |
|---|---|
| `preferLocalColumns(['updated_by'])` | Keep the device's own edits for a set of columns; take the remote for the rest. |
| `preferRemoteColumns(['role'])` | Mirror server-managed fields; keep local for everything else. |
| `maxOf(['counter'])` | Take the max of a numeric counter (monotonic increments). Falls back to LWW for non-counter columns. |

Example (per-user / per-field merge):

```dart
final policy = ConflictPolicy.custom(
  MergeStrategies.preferLocalColumns(<String>['display_name']),
);
// A's `display_name` + B's `role` + remote for everything else.
```

### Back-compat shims

`LwwConflictResolver.instance` and
`CustomConflictResolver.wrap(...)` are retained
for back-compat and behave identically to
`ConflictPolicy.lww` and
`ConflictPolicy.custom(...)`, respectively. New
code should use `ConflictPolicy`; the shims are
kept so existing sync code does not break.

## Triggers

A `SyncTrigger` is what fires the `syncAsync` call.
Three reference implementations ship in the box:

| Class | Fires when |
|---|---|
| `ManualSyncTrigger` | The user calls `trigger.fire()`. Exposed for integration with custom event sources (a custom network-reconnect listener, an app-lifecycle observer, etc.). |
| `SignalSyncTrigger` | A `dart:async` `Completer`-like signal. Programmatic; useful for tests. |
| `PeriodicSyncTrigger` | Every `interval` (e.g. every 30 seconds). Battery-friendly background fallback. |

The `SyncTrigger` interface:

```dart
abstract class SyncTrigger {
  void start(Future<void> Function() onTrigger);
  void stop();
}
```

Wire them up with `DbContext.startSyncTriggers`:

```dart
ctx.startSyncTriggers(
  provider: restProvider,
  triggers: [
    PeriodicSyncTrigger(interval: Duration(seconds: 30)),
    ManualSyncTrigger(),  // for the user's custom integration
  ],
  stateStore: fileStateStore,
);
```

`stopSyncTriggers` is safe to call multiple times
and is called automatically on context dispose.

## State

`SyncStateStore` persists the `clientId` and
`clientWatermark` between runs. Five methods:

```dart
abstract class SyncStateStore {
  Future<String?> getClientIdAsync();
  Future<void> setClientIdAsync(String clientId);
  Future<int> getWatermarkAsync();    // defaults to 0
  Future<void> setWatermarkAsync(int watermark);
  Future<void> clearAsync();
}
```

Two bundled implementations:

| Class | Backing store |
|---|---|
| `InMemorySyncStateStore` | `Map<String, Object?>` (no I/O). For tests and dev. |
| `FileSyncStateStore` | A JSON file on disk. For production. |

### `bootstrapSync`

A one-shot helper that loads (or generates + persists)
the `clientId` and the watermark. Call it once at app
startup alongside `initializeDAsync`:

```dart
final ctx = MyDbContext(sqliteProvider);
await ctx.initializeDAsync();                 // migrate + seed
await ctx.bootstrapSync(fileStateStore);      // sync identity

// Optionally start the periodic trigger:
ctx.startSyncTriggers(
  provider: restProvider,
  triggers: [PeriodicSyncTrigger(...)],
  stateStore: fileStateStore,
);
```

## Implementations

### `RestSyncProvider`

```dart
final restProvider = RestSyncProvider(
  baseUrl: 'https://api.example.com',
  client: RetryingHttpClient(
    inner: HttpPackageClient(),
    policy: ExponentialBackoffRetryPolicy(maxAttempts: 3),
  ),
  headers: {'Authorization': 'Bearer $token'},
  timeout: Duration(seconds: 15),
);
```

Wire format (POST `$baseUrl/sync` body):

```json
{
  "clientId": "client-1234567890-789",
  "since": 12345,
  "changes": [
    {
      "tableName": "orders",
      "pk": "42",
      "type": "upsert",
      "payload": {"id": 42, "total": 99.95, "status": "paid"},
      "version": 1700000000000
    }
  ]
}
```

The server response is the same shape (the
remote-side `changes` are what the client applies).

The watermark endpoint (`GET $baseUrl/sync/watermark`)
returns a plain int (as a `String` in the response
body, parsed via `int.parse(response.rawBody.trim())`).

### `InMemorySyncProvider`

```dart
final inMemory = InMemorySyncProvider(clientId: 'client-A');
```

No I/O. Stores every push in a shared history,
re-stamps each `SyncChange.version` with a
server-side watermark (so all clients see a
consistent ordering regardless of what the
client sent), and returns the changes that
happened AFTER the client's `since`, MINUS the
changes the client itself just pushed (so it
does not re-apply its own work). For tests and
dev.

| Member | Purpose |
|---|---|
| `InMemorySyncProvider({String? clientId})` | Auto-generated id `memory-<micros>` if none provided. |
| `pushLog` | Read-only log of every envelope received. Useful for asserting what was sent. |
| `reset()` | Clears history, watermarks, and `pushLog`. Call from `setUp`. |
| `injectChange(SyncChange)` | Simulates a server-side change. Re-stamps `version` with the next watermark. |

A second `InMemorySyncProvider` instance with
the same `clientId` can simulate a remote client:

```dart
final a = InMemorySyncProvider(clientId: 'A');
final b = InMemorySyncProvider(clientId: 'B');
await a.syncAsync(SyncEnvelope(clientId: 'A', since: 0, changes: [cA]));
final envelope = await b.syncAsync(SyncEnvelope(clientId: 'B', since: 0, changes: []));
// envelope.changes contains A's change (filtered against B's own push).
```

## `SyncTransport` and multi-transport providers

Four transports are supported, each modeled by
the `SyncTransport` enum:

| Value | Direction | Latency | Use case |
|---|---|---|---|
| `polling` | client → server (pull) | high (5-60s) | Default; always works. |
| `webSocket` | bidirectional | low (<100ms) | Real-time push from server. |
| `sse` | server → client (push) | medium (1-5s) | Push fallback when WS not available. |
| `udp` | bidirectional | very low (<10ms) | Real-time / lossy ephemeral state. |

### `WebSocketSyncProvider`

A `SyncProvider` that uses a WebSocket to receive
server-pushed changes in addition to the normal
push/pull round-trip:

```dart
final ws = WebSocketSyncProvider(
  url: Uri.parse('wss://api.example.com/sync'),
  pushHandler: (change) async => ctx.applyRemote(change),
  auth: () async => myAuth.token,    // called on reconnect
  channel: myChannelFactory,         // optional; default is a no-op
);
await ws.connect();
```

| Parameter | Purpose |
|---|---|
| `url` | The `wss://` endpoint. |
| `pushHandler` | Called for every server-pushed `PushedSyncChange`. |
| `auth` | Optional async function that returns the current auth header value. Called on each (re)connect. |
| `channel` | Optional WebSocket channel factory (defaults to a no-op). Tests inject a fake here. |

`PushedSyncChange` wraps a `SyncChange` with a
`receivedAt` timestamp and an optional
`originServerId` (for sharded multi-server
setups).

> **2.0.0 limitation.** `syncAsync` throws
> `UnsupportedError` because the round-trip
> requires an injected transport (see the
> example in the file). Use it together with
> `RestSyncProvider` for the polling side; the
> full realtime integration ships in 2.1.0.

### `MultiTransportSyncProvider`

Orchestrates up to four `SyncProvider`s and
picks the best one per direction:

```dart
final multi = MultiTransportSyncProvider(
  polling: RestSyncProvider(...),       // always-available fallback
  webSocket: WebSocketSyncProvider(...), // primary push
  sse: SseSyncProvider(...),            // fallback push
  udp: UdpSyncProvider(...),            // optional, real-time
);
await multi.connect();
await ctx.syncAsync(multi);
```

| Field | Role |
|---|---|
| `polling` (required) | Source of truth for the pull side. |
| `webSocket` | Primary push transport. |
| `sse` | Fallback push transport. |
| `udp` | Optional real-time transport. |

`activeTransport` reports which transport is
currently in use; `transportChanges` is a
broadcast stream of those transitions.

## Retry policies — extended set

`d_rocket` 2.0.0 ships three additional policies
on top of the 1.x `ExponentialBackoffRetryPolicy`
and `NoRetryPolicy`:

| Policy | Behaviour | Constructor |
|---|---|---|
| `LinearBackoffRetryPolicy` | Fixed delay between attempts. | `LinearBackoffRetryPolicy({delay = 1s, maxAttempts = 3})` |
| `FibonacciBackoffRetryPolicy` | Fibonacci-spaced delays (1, 1, 2, 3, 5, 8, 13, …). | `FibonacciBackoffRetryPolicy({unitDelay = 1s, maxAttempts = 5})` |
| `DecorrelatedJitterRetryPolicy` | AWS-style decorrelated jitter. Next delay is uniform between `baseDelay` and `min(cap, prev * 3)`. | `DecorrelatedJitterRetryPolicy({baseDelay = 100ms, cap = 30s, maxAttempts = 5})` |

Example:

```dart
final retry = DecorrelatedJitterRetryPolicy(
  baseDelay: const Duration(milliseconds: 100),
  cap: const Duration(seconds: 30),
  maxAttempts: 5,
);
await ctx.syncAsync(provider, retryPolicy: retry);
```

The `DecorrelatedJitterRetryPolicy` lower the
collision rate compared to vanilla exponential
backoff in multi-client scenarios (see the
[AWS architecture blog](https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/)).

## `SyncStateStore` implementations

Three reference implementations ship with the
sync layer. All implement the
`SyncStateStore` contract (5 methods: get/set
`clientId`, get/set `watermark`, `clear`).

| Class | Backing store | Platform |
|---|---|---|
| `InMemorySyncStateStore` | `Map<String, Object?>` | Tests / dev. |
| `FileSyncStateStore` | JSON file on disk | Dart VM / server / Flutter mobile (via `path_provider`). |
| `FileSyncStateStore` (web stub) | Throws `UnsupportedError` | Web; replace with a `package:shared_preferences` adapter. |

### `InMemorySyncStateStore`

```dart
final store = InMemorySyncStateStore(
  initialClientId: 'client-A',
  initialWatermark: 0,
);
```

No I/O. Constructor accepts seed values for
tests.

### `FileSyncStateStore` (native, `dart:io`)

```dart
final store = FileSyncStateStore('/data/sync_state.json');
```

Persists the state to a JSON file:

```json
{
  "clientId": "client-1234",
  "watermark": 42
}
```

The file is created lazily on the first write;
parent directories are created recursively.

### `FileSyncStateStore` (web stub)

On the web, `dart:io` is not available, so the
class is a conditional-import stub that throws
`UnsupportedError` on every call:

```
UnsupportedError: FileSyncStateStore is not available on the web.
Use a `package:shared_preferences`-backed `SyncStateStore` adapter.
```

The public contract is preserved, so the call
site does not change once a
`SharedPreferencesSyncStateStore` adapter is
wired in.

## `SyncQueueStore`

Backing store for the persistent
`pendingSyncChanges` queue (since 1.1.1). The
queue lives in a `d_rocket_sync_queue` table
inside the user database (so SQLCipher
encryption is inherited for free). All INSERTs
run inside the caller's transaction, so a
crash between `saveChangesAsync` and the next
`syncAsync` does not lose queued changes.

The store is internal — the public API
(`DbContext.saveChangesAsync`, `syncAsync`,
`pendingSyncChanges`) is unchanged. Existing
callers get persistence with no opt-in.

| Member | Purpose |
|---|---|
| `static const tableName = 'd_rocket_sync_queue'` | The on-disk table name. |
| `maxQueueSize` (default 10,000) | Cap; the oldest rows are dropped when exceeded (with a `print` warning). |
| `enqueue(SyncChange)` | Appends a change to the queue (in the caller's transaction). |
| `loadAll()` | Returns every queued change in insertion order. |
| `clearAll()` | Empties the queue (called by `syncAsync` after a successful round-trip). |
| `count()` | Cheap row count. |

`SyncQueueStore` is not exported from the
package barrel — it is an implementation
detail of `DbContext`.

## `SyncProgress` and `SyncMetrics` (observability)

### `SyncProgress`

A value-typed event emitted during a sync
round-trip. Used by the UI to render a
"Syncing 247/1000..." spinner and by tests to
assert on phase ordering.

| Field | Type | Purpose |
|---|---|---|
| `phase` | `SyncPhase` | The current high-level phase. |
| `processed` | `int` | Items processed in this phase. |
| `total` | `int?` | Total items expected (null when unknown). |
| `message` | `String?` | Human-readable (delay for `retrying`, error text for `error`). |
| `error` | `Object?` | Set when `phase == SyncPhase.error`. |
| `stackTrace` | `StackTrace?` | Set when `phase == SyncPhase.error`. |
| `timestamp` | `DateTime` | When the event was created. |
| `fraction` | `double?` | `processed / total`, clamped to `[0, 1]` (null when total is unknown). |

The `SyncPhase` enum has 7 values: `starting`,
`pushing`, `pulling`, `applying`, `retrying`,
`done`, `error`. Transitions are:

```
starting → pushing → (retrying →) pulling → applying → (retrying →) done | error
```

Subscribers consume via `ctx.syncProgress`
(a `Stream<SyncProgress>` with replay-1 of
the latest event) or the
`syncAsync(..., onProgress: (p) {...})`
callback variant.

### `SyncMetrics`

A recorder that ships a
`SyncMetricsSnapshot` on every round-trip:

```dart
ctx.metrics.stream.listen((snapshot) {
  print('avg=${snapshot.avgDurationMicros}μs '
        'p95=${snapshot.p95DurationMicros}μs '
        'roundTrips=${snapshot.roundTrips}');
});
```

A snapshot has 9 fields: `roundTrips`,
`changesPushed`, `changesPulled`,
`changesApplied`, `conflicts`, `errors`,
`avgDurationMicros`, `p95DurationMicros`,
`timestamp`.

The stream is broadcast with replay-1 so a
late subscriber gets the latest snapshot.

## `SyncFilter` (selective sync)

A `SyncFilter` decides which `SyncChange`s are
pushed and which remote changes are applied.
Without a filter, every `syncAsync` call ships
and applies every change.

```dart
abstract interface class SyncFilter {
  bool matches(SyncChange change);
  String get name;
}
```

Four bundled implementations:

| Class | Behaviour |
|---|---|
| `AllowAllSyncFilter` | No filter (the default). |
| `TableNameSyncFilter(Set<String>)` | Include only changes for the given table(s). |
| `RecordSyncFilter({tableName, predicate})` | Include only rows matching `(Map<String, Object?> row) -> bool`. |
| `ScopedSyncFilter.and([...])` / `.or([...])` | Compose filters (AND / OR). |

```dart
// Per-user AND per-table.
final filter = ScopedSyncFilter.and(<SyncFilter>[
  TableNameSyncFilter(<String>{'orders'}),
  RecordSyncFilter(
    tableName: 'orders',
    predicate: (Map<String, Object?> row) => row['userId'] == me.id,
  ),
]);
await ctx.syncAsync(provider, filters: <SyncFilter>[filter]);
```

Use cases: per-user sync, per-table sync
(e.g. "only sync `orders` right now"),
time-windowed sync, privacy filters
(e.g. "never sync `isDeleted = true`").

## `SyncSchema` (versioning)

`SyncSchemaVersion` is an integer version
counter that the caller tracks (e.g. in a
`d_rocket_meta` table). The
`checkSchema(local, remote)` helper returns:

| Result | Meaning |
|---|---|
| `SyncSchemaResult.ok` | Schemas compatible; proceed. |
| `SyncSchemaResult.needsMigration` | Remote is newer; run a migration. |
| `SyncSchemaResult.serverOutOfDate` | Local is newer than the server (unusual). |

```dart
const local = SyncSchemaVersion(2);
const remote = SyncSchemaVersion(3);
final SyncSchemaResult result = checkSchema(local: local, remote: remote);
// result == SyncSchemaResult.needsMigration
```

`SyncSchemaVersion.initial` is
`SyncSchemaVersion(0)`; `bumped()` returns
`value + 1`.

## `AuthRefreshSync` (auto-refresh on 401)

When a sync round-trip fails with HTTP 401
(Unauthorized), the auth token has probably
expired. `AuthRefreshHandler` calls the
user's `onUnauthenticated` callback to
refresh the token and retries the operation:

```dart
final handler = AuthRefreshHandler(
  onUnauthenticated: (Object e) async {
    return await myAuthService.refresh();
  },
  maxRefreshAttempts: 2,
);
```

| Member | Purpose |
|---|---|
| `onUnauthenticated` | The refresh callback; returns the new token (or null to give up). |
| `maxRefreshAttempts` | Maximum refresh attempts before giving up (default 1). |
| `tryRefresh(error)` | Calls `onUnauthenticated` if the budget allows. |
| `reset()` | Clears the attempt counter — call after a successful sync. |

The `withAuthRefresh` helper wraps any
operation with this logic. The default
`defaultIsUnauthenticated` detector checks
whether the error has a `statusCode == 401`
property (works for `RestHttpException` and
similar).

## `ConnectivityProvider` (online / offline)

The `ConnectivityProvider` abstraction tells
the sync layer what network is available. The
sync layer uses it to skip sync when offline,
throttle on cellular, or pick a different
transport.

| Class | Behaviour |
|---|---|
| `NoopConnectivityProvider` | Default; always returns `ConnectivityState.wifi`. Tests + desktop. |
| `GatedConnectivityProvider` | Wraps an inner provider and applies a predicate (e.g. "sync only on wifi"). |
| `ConnectivityPlusProvider` | Backed by `package:connectivity_plus` (in `d_rocket_engine_mobile`, 2.1.0). |

The `NetworkType` enum has 6 values: `none`,
`wifi`, `cellular`, `vpn`, `ethernet`,
`unknown`. `ConnectivityState` exposes
`isUnmetered` and `isMetered` helpers.

```dart
final ConnectivityProvider conn = GatedConnectivityProvider(
  inner: NoopConnectivityProvider(),
  predicate: (ConnectivityState s) => s.networkType == NetworkType.wifi,
);
final trigger = PeriodicSyncTrigger(
  interval: const Duration(minutes: 5),
  connectivity: conn,
);
```

The `changes` stream is broadcast with
replay-1. `NoopConnectivityProvider.setState`
is a test helper to flip the simulated state.

## `MultiTenantSync` (per-tenant isolation)

A `TenantId` is a string (`acme-corp`, etc.).
The `MultiTenantSyncStateStore<S>` wrapper
keeps one inner store per tenant and dispatches
by tenant:

```dart
final multi = MultiTenantSyncStateStore<FileSyncStateStore>(
  (TenantId t) => FileSyncStateStore('/data/${t.value}.json'),
);
final FileSyncStateStore acme = multi.storeFor(const TenantId('acme-corp'));
final FileSyncStateStore globex = multi.storeFor(const TenantId('globex'));
```

Each tenant has its own `clientId` and
watermark; the same `SyncProvider` can serve
multiple tenants without state bleeding.

## `SyncPriority` and `VectorClock`

### `SyncPriority`

An ordering hint for triggers that fire in
the same event-loop tick. Higher = fires
first.

| Constant | Value |
|---|---|
| `SyncPriority.critical` | 1000 (auth refresh, security alerts) |
| `SyncPriority.high` | 100 (visible screen) |
| `SyncPriority.normal` | 0 (default) |
| `SyncPriority.low` | -100 (background reconciliation) |
| `SyncPriority.background` | -1000 (analytics) |

`firesBefore(other)` compares two priorities.

### `VectorClock`

A `Map<String, int>` of `clientId -> counter`,
used for clock-skew-free ordering of concurrent
edits:

| Method | Behaviour |
|---|---|
| `VectorClock.empty()` | An empty clock. |
| `counterFor(clientId)` | Returns 0 if no counter for the client. |
| `increment(clientId)` | Increments and returns the new value. |
| `merge(other)` | Takes the max of each counter. |
| `isAfter(other)` | Happens-before: at least one counter higher and none lower. |
| `isConcurrentWith(other)` | Neither is after the other. |

```dart
final a = VectorClock.empty()..increment('client-A');
final b = VectorClock.empty()..increment('client-B');
final isConcurrent = a.isConcurrentWith(b); // true
```

## `RestSyncException`

A `RestSyncException` is thrown when a sync
round-trip encounters a non-2xx response. It
wraps the underlying transport exception
(`RestHttpException`, `NetworkException`, etc.)
so callers can catch a sync-specific error
without knowing the transport:

```dart
try {
  await ctx.syncAsync(provider);
} on RestSyncException catch (e) {
  print('Sync failed: ${e.message} (cause: ${e.cause})');
}
```

| Field | Purpose |
|---|---|
| `message` | Human-readable description. |
| `cause` | The wrapped underlying exception (nullable). |

## `FileSync` (binary blobs)

`FileSyncReference` is a placeholder inside a
regular `SyncChange` payload that points to a
binary blob stored elsewhere (typically cloud
storage):

```dart
final ref = FileSyncReference(
  tableName: 'attachments',
  pk: '42',
  field: 'photo',
  remoteUrl: 'https://cdn.example.com/photo.jpg',
  sizeBytes: 1024000,
  contentType: 'image/jpeg',
);
```

| Field | Purpose |
|---|---|
| `tableName` | The local table that owns the file. |
| `pk` | The primary key of the owner row. |
| `field` | The field name (`photo`, `pdf`, …). |
| `remoteUrl` | Where the file lives in cloud storage. |
| `sizeBytes` | File size in bytes. |
| `contentType` | The MIME type. |

In 2.0.0, `FileSyncProvider` is a stub — the
actual upload/download is the user's
responsibility (typically `package:dio` or
`package:http`).

## Common pitfalls

### "My local changes don't reach the server"

Check that `d_rocket_sync_queue` is non-empty. The
queue is populated by `saveChanges` AND
`saveChangesAsync` (both paths share the
persistence, since 1.1.1).

```dart
ctx.orders.add(order);
await ctx.saveChangesAsync();   // queue is populated
print(ctx.pendingSyncChanges.length);   // 1
await ctx.syncAsync(restProvider);    // flushes
print(ctx.pendingSyncChanges.length);   // 0
```

### "Server changes aren't appearing in my UI"

The pull response is consumed by the orchestrator,
which applies each `SyncChange` to the local
database. The UI sees the change via `DbSet.watch()`,
which re-emits on every `ChangeTracker.changes`
event.

Make sure your widget is wired to the stream:

```dart
StreamBuilder<List<Order>>(
  stream: ctx.orders.watch(),
  // ...
);
```

### "The queue grows without bound"

The `d_rocket_sync_queue` table is on disk. If
`syncAsync` is never called (or always fails), the
queue grows on every `saveChanges`. To guard
against runaway growth, `SyncQueueStore` ships a
`maxQueueSize` parameter (default 10,000) that
throws a `StateError` when the cap is hit:

```dart
if (ctx.pendingSyncChanges.length > 1000) {
  throw StateError('Pending sync queue is too large — sync failed?');
}
```

A future iteration may add a "drop oldest" policy
similar to a real offline queue.

### "The watermark regresses"

The watermark is advanced only on a successful
`syncAsync`. If the user mutates the
`SyncStateStore` directly (e.g. wipes the file),
the next `syncAsync` will start from `since: 0`
and the server will re-send every change. This is
correct for "wipe server history" scenarios; it's
not what you want for "advance to a checkpoint"
scenarios. For the latter, use
`bootstrapSync(forceNewId: true)` to get a fresh
identity and start from scratch.

## API reference

### `SyncProvider` / `RestSyncProvider` / `InMemorySyncProvider` / `WebSocketSyncProvider` / `MultiTransportSyncProvider`

Abstract backend (2 methods: `syncAsync`, `currentWatermarkAsync`) plus four implementations: REST, in-memory, WebSocket, and multi-transport orchestration.

### `SyncTransport`

Enum: `polling`, `webSocket`, `sse`, `udp`.

### `SyncEnvelope` / `SyncChange` / `SyncChangeType`

Data classes / enum. `SyncChangeType` has 2 values:
`upsert`, `delete`.

### `ConflictResolver` / `ConflictPolicy` / `LwwConflictPolicy` / `ClientWinsConflictPolicy` / `CustomConflictPolicy` / `MergeStrategies` / `LwwConflictResolver` / `CustomConflictResolver`

Typed conflict-resolution API. See [Conflict resolution](#conflict-resolution).

### `SyncStateStore` / `InMemorySyncStateStore` / `FileSyncStateStore` (native + web stub)

Persistence for `clientId` and `clientWatermark`. Five methods on the interface.

### `SyncQueueStore`

Internal on-disk backing for `pendingSyncChanges` (table `d_rocket_sync_queue`). See [SyncQueueStore](#syncqueuestore).

### `SyncTrigger` / `ManualSyncTrigger` / `SignalSyncTrigger` / `PeriodicSyncTrigger`

The trigger interface plus three reference
implementations.

### `RetryPolicy` / `ExponentialBackoffRetryPolicy` / `LinearBackoffRetryPolicy` / `FibonacciBackoffRetryPolicy` / `DecorrelatedJitterRetryPolicy` / `NoRetryPolicy` / `RetryDecision`

Retry policy for the round-trip. See [Layer 2 — REST](05-layer-2-rest.md#retry-policies-from-the-sync-layer)
for the contract; the sync layer adds three more variants.

### `SyncProgress` / `SyncPhase` / `SyncProgressEventBus`

Per-round-trip value-typed events. See [SyncProgress and SyncMetrics](#syncprogress-and-syncmetrics-observability).

### `SyncMetrics` / `SyncMetricsSnapshot`

Telemetry recorder. See [SyncProgress and SyncMetrics](#syncprogress-and-syncmetrics-observability).

### `SyncFilter` / `AllowAllSyncFilter` / `TableNameSyncFilter` / `RecordSyncFilter` / `ScopedSyncFilter`

Selective-sync filters. See [SyncFilter](#syncfilter-selective-sync).

### `SyncSchemaVersion` / `SyncSchemaResult` / `checkSchema`

Schema-version comparison. See [SyncSchema](#syncschema-versioning).

### `AuthRefreshHandler` / `withAuthRefresh` / `defaultIsUnauthenticated` / `IsUnauthenticatedFn`

401-triggered token refresh. See [AuthRefreshSync](#authrefreshsync-auto-refresh-on-401).

### `ConnectivityProvider` / `ConnectivityState` / `NetworkType` / `NoopConnectivityProvider` / `GatedConnectivityProvider`

Online/offline detection. See [ConnectivityProvider](#connectivityprovider-online--offline).

### `TenantId` / `MultiTenantSyncStateStore`

Per-tenant sync state. See [MultiTenantSync](#multitenantsync-per-tenant-isolation).

### `SyncPriority`

Trigger ordering. See [SyncPriority](#syncpriority-and-vectorclock).

### `VectorClock`

Clock-skew-free ordering. See [VectorClock](#syncpriority-and-vectorclock).

### `RestSyncException`

Exception type for non-2xx sync responses.

### `FileSyncReference`

Placeholder inside a `SyncChange` for binary blobs. See [FileSync](#filesync-binary-blobs).

### `DbContext.syncAsync` (and helpers)

| Member | Purpose |
|---|---|
| `pendingSyncChanges` | Snapshot of the in-memory pending queue. |
| `startSyncTriggers({provider, triggers, stateStore})` | Start a list of triggers. |
| `stopSyncTriggers()` | Stop every active trigger. |
| `bootstrapSync(store, {forceNewId})` | One-shot sync-identity setup. |
| `clientId` | The persisted clientId (or `null`). |
| `syncAsync(provider, {clientId, stateStore, retryPolicy, filters, onProgress})` | The 3-step orchestrator. |
| `syncProgress` | `Stream<SyncProgress>` with replay-1 of the latest event. |
| `metrics` | The `SyncMetrics` recorder for this context. |
| `connectivity` | The `ConnectivityProvider` for this context. |
