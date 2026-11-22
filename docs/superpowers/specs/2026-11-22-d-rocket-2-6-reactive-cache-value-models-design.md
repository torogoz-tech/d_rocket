# d_rocket 2.6.0 Functional Parity Program

## Goal

Extend the data layer for network-first applications while closing the main
functional gaps identified across forms, serialization, REST, SQLite ORM,
realtime communication, synchronization, contracts and testing. The release
must remain framework-independent: no dependency on Flutter, Bloc, Riverpod or
another presentation framework is introduced into the core packages.

## Scope

### Reactive REST queries

Add two method annotations:

```dart
@QueryCache(
  tags: <String>['account:{id}'],
  staleTime: Duration(seconds: 30),
)
Stream<Account> watchAccount(@Path('id') String id);

@Invalidates(<String>['account:{request.sourceAccountId}', 'recent_movements'])
Future<TransferReceipt> executeTransfer(@Body() TransferRequest request);
```

The generated client must use an instance-scoped `RestQueryCache` that:

- deduplicates concurrent requests for the same normalized GET key;
- retains successful values for a configurable stale/cache lifetime;
- exposes a `Stream<T>` for active subscribers;
- refetches active queries after a successful mutation invalidates a matching tag;
- supports path, query, header and body-property tag placeholders without
  evaluating arbitrary code;
- clears values, registrations and pending cache work through
  `dRest.clearQueryCache()` / the cache instance;
- never includes credentials in keys or diagnostic events;
- propagates HTTP and conversion errors to the query stream;
- does not poll, own UI state, or introduce Flutter dependencies.

Invalidation runs only after the annotated mutation returns successfully.
Failed mutations do not invalidate cached data. `clear()` advances a cache
generation so a late response cannot repopulate data after logout.

### Generated value-model helpers

Extend `@Serializable` with additive opt-in flags:

```dart
@Serializable(copyWith: true, equality: true)
class Account {
  const Account({required this.id, required this.balance});

  final String id;
  final double balance;
}
```

`copyWith: true` emits a typed extension using a private sentinel so nullable
fields can distinguish “keep the current value” from “set null”.

Because a Dart builder cannot reopen an existing class and inject `==` or
`hashCode`, `equality: true` emits a generated mixin and requires the model to
opt into it explicitly:

```dart
class Account with _$AccountEquality { ... }
```

The builder must produce a clear generation error when the flag is enabled but
the generated mixin is not applied. Equality uses all declared serializable
fields and a deterministic deep comparison/hash for lists, sets and maps.
No equality or copyWith code is emitted by default.

## Functional coverage for 2.6.0

The cache and value helpers are only two parts of the release. The following
capabilities are part of the 2.6.0 program and must be tracked as separate,
testable workstreams.

### Forms and field state

- Nested `FormGroup` models and dynamic `FormArray` collections.
- Runtime add/remove of controls while preserving validation and touched state.
- `dirty`/`pristine`, `enabled`/`disabled`, `pending`, reset and default-value
  semantics.
- Composable synchronous and asynchronous validators, including debounce for
  remote validation and reusable cross-field validators.
- Built-in validators for comparison, matching, membership, containment,
  `requiredTrue`, credit-card values and other common data-layer rules.
- A consistent mapping from typed REST errors to field and form errors.
- Binding metadata for composite fields without requiring one controller per
  input and without introducing framework-specific widgets.

### Serialization and schema contracts

- Extensible `JsonConverter<T, Object?>` and field-level `readValue` hooks.
- Global, class-level and field-level converter configuration.
- Explicit unknown-field policy: ignore, preserve or fail, selected by the
  caller rather than hidden in generated code.
- Options for null inclusion, explicit nested JSON conversion, factory and
  `toJson` generation, and field-name strategies.
- Complete handling for dates, decimals, enums, UUIDs, nullable nested models,
  generic envelopes and opaque JSON payloads, with field-path diagnostics when
  conversion fails.
- JSON Schema export and golden-schema tests for generated models.

### SQLite ORM and LINQ

The LINQ and query work in this release remains SQLite-focused, as agreed.

- Typed manager/query APIs, composable predicates, ordering, paging and
  reactive query granularity.
- Companion-style partial insert/update values and extensible SQLite type
  converters.
- Declarative custom SQL, validated SQL files, custom functions and aggregate
  registration without bypassing the normal parameterization rules.
- Migration/schema inspection, generated migration tests and explicit review
  output for destructive `ALTER TABLE`, drops and type changes.
- Read/query execution policies that can use isolates or a read pool where the
  host supports them, without changing the SQLite contract.

### REST contracts and transfers

- OpenAPI 3.1 export/import for annotated clients, including typed errors and
  pagination metadata.
- Declarative pagination and endpoint-specific serializers/converters.
- Multipart upload/download APIs with progress and streaming of large bodies.
- Auth-refresh integration, richer retry policies and typed RFC 7807/error
  mapping while preserving transport ownership and cancellation semantics.
- The reactive query cache and tag invalidation described above.

### Realtime communication

- Shared lifecycle, retry, heartbeat, backpressure and delivery-ack contracts
  for SSE and WebSocket clients.
- Reconnect jitter, multiplexed channels and queued outbound messages with an
  explicit delivery policy.
- Observable connection state, HTTP/auth status and safe cancellation across
  `start`, `stop`, `dispose` and restart cycles.
- Transport adapters may add Socket.IO or platform-specific negotiation, but
  those are adapters/candidates and are not required dependencies of the core.

### Offline-first synchronization

- Delta/incremental synchronization, partial entity/field sync and
  conflict-specific retry policies.
- Durable sync queue, resumable file attachment transfer and persistent sync
  metrics, with clear ownership of sensitive in-memory data.
- Data-layer conflict inspection and resolution contracts; UI conflict screens
  remain outside the core package.
- Native background scheduling remains in mobile/Flutter adapters. CRDTs are a
  candidate extension, not a mandatory core dependency for 2.6.0.

### Contracts, tooling and verification

- Generated API documentation, error contracts, form metadata and schema/entity
  diagrams where the source annotations provide enough information.
- REST mocks, fake HTTP server fixtures, migration-generated tests, OpenAPI
  contract tests, benchmarks and codegen matrices across supported analyzer
  versions.
- Compatibility verification for Dart 3.11.5, 3.12 and 3.13, stable Flutter,
  and the supported Web, Android, iOS, macOS and Linux targets where the
  package is applicable. Published-package resolution must be tested in
  addition to path-based workspace tests.

## Boundary decisions

- Core packages stay pure Dart/data-layer packages. Flutter widgets, Bloc,
  Riverpod, DevTools UI, native background schedulers and conflict-resolution
  screens belong in adapters or separate products.
- SQLite remains the only ORM/LINQ target for this program; this does not
  reopen the earlier decision to add unrelated database engines.
- Socket.IO, CRDTs, testcontainers and platform-specific transfer/scheduler
  integrations are planned extension points. They receive contracts and
  compatibility tests only when an adapter is implemented; they are not used
  as hidden core dependencies.

## Non-goals

- No Flutter widgets or Bloc/Riverpod adapters.
- No framework-specific UI state manager or widget implementation.
- No native background scheduler in the pure-Dart core.
- No GraphQL or arbitrary server cache protocol in this release.
- No mutation of user source files or generated files committed manually.
- No automatic equality injection that Dart's part-file model cannot support.

## Compatibility

- Dart 3.11.5, 3.12 and 3.13.
- Existing `HttpCache`, `RestClient`, serializer and generated clients remain
  source-compatible when the new annotations/options are absent.
- No new runtime package dependency is required.
