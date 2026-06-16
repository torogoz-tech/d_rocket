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

The `pendingSyncChanges` queue is **in-memory** (not
persisted to SQLite). It is populated by
`saveChangesAsync` after a successful commit and
drained by `syncAsync` on a successful round-trip.
A failed sync keeps the queue intact (the next
`syncAsync` retries the same changes).

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

1. **Push.** Drain `_pendingSyncChanges` (populated
   by `saveChangesAsync` after a successful commit)
   into a `SyncEnvelope` with the current
   `_clientWatermark` as `since`.
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

The conflict-resolution contract is a simple
typedef:

```dart
typedef ConflictResolver = Map<String, Object?> Function(
  Map<String, Object?> localRow,
  Map<String, Object?> remotePayload,
);
```

The resolver receives the current local row and the
remote payload, and returns the merged row to apply.

The default resolver is `LwwConflictResolver.instance`:
last-write-wins, which simply takes the remote
payload verbatim (a shallow `{...remote}` spread).

To use a custom resolver, pass it to the context's
`applyRemoteChange` (or wrap the orchestrator
yourself). The framework's default behaviour is
LWW; the user can override per-row or per-table.

`d_rocket` 1.1.0 also ships a typed
`ConflictPolicy` hierarchy that is the preferred
API over the bare `ConflictResolver` typedef.
Four built-in constants are exposed:

```dart
final ConflictPolicy serverWins = ConflictPolicy.lww;      // remote
final ConflictPolicy clientWins = ConflictPolicy.clientWins; // local
final ConflictPolicy columnAware = ConflictPolicy.custom(
  MergeStrategies.preferLocalColumns(<String>['updated_by']),
);
```

The `LwwConflictResolver.instance` and
`CustomConflictResolver.wrap(...)` shims are
retained for back-compat and behave identically
to `ConflictPolicy.lww` and
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
final inMemory = InMemorySyncProvider();
```

No I/O. Stores envelopes in a `List<SyncChange>`. For
tests and dev. The user can inject pre-set "remote"
envelopes via a test helper.

## Common pitfalls

### "My local changes don't reach the server"

Check that `pendingSyncChanges` is non-empty. The
queue is populated by `saveChangesAsync` (NOT
`saveChanges`). If you're using the sync
`saveChanges()` (the non-transactional path), the
queue is not populated.

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

`pendingSyncChanges` is in-memory. If `syncAsync` is
never called (or always fails), the queue grows on
every `saveChangesAsync`. To guard against runaway
memory, the user can cap the queue size manually:

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

### `SyncProvider`

Abstract backend. Methods: `syncAsync(envelope)`,
`currentWatermarkAsync()`.

### `RestSyncProvider`

HTTP + JSON implementation. Constructor:
`(baseUrl, client?, headers?, timeout?)`.

### `InMemorySyncProvider`

Test fixture. No I/O.

### `SyncEnvelope` / `SyncChange` / `SyncChangeType`

Data classes / enum. `SyncChangeType` has 2 values:
`upsert`, `delete`.

### `ConflictResolver` / `LwwConflictResolver`

`ConflictResolver` is a typedef. `LwwConflictResolver.instance`
is the default (last-write-wins).

### `SyncStateStore` / `InMemorySyncStateStore` / `FileSyncStateStore`

Persistence for `clientId` and `clientWatermark`.
Five methods on the interface.

### `SyncTrigger` / `ManualSyncTrigger` / `SignalSyncTrigger` / `PeriodicSyncTrigger`

The trigger interface plus three reference
implementations.

### `RetryPolicy` / `ExponentialBackoffRetryPolicy` / `NoRetryPolicy` / `RetryDecision`

Retry policy for the round-trip. See [Layer 2 — REST](05-layer-2-rest.md#retry-policies-from-the-sync-layer)
for the contract; lives in the sync layer.

### `DbContext.syncAsync` (and helpers)

| Member | Purpose |
|---|---|
| `pendingSyncChanges` | Snapshot of the in-memory pending queue. |
| `startSyncTriggers({provider, triggers, stateStore})` | Start a list of triggers. |
| `stopSyncTriggers()` | Stop every active trigger. |
| `bootstrapSync(store, {forceNewId})` | One-shot sync-identity setup. |
| `clientId` | The persisted clientId (or `null`). |
| `syncAsync(provider, {clientId, stateStore, retryPolicy})` | The 3-step orchestrator. |
