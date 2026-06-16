/// 🚀 d_rocket — Dart's data rocket.
///
/// `d_rocket` is a unified package for the four pillars of data
/// handling in Dart/Flutter applications:
///
/// 1. LINQ-style queries — `IQueryable<T>` with deferred execution.
/// 2. Serialization — annotation-driven `toJson` / `fromJson`.
/// 3. REST with steroids — typed HTTP client with interceptors,
/// wrap-around clients (retry, rate limit, circuit breaker), and
/// cancelable requests.
/// 4. ORM (SQLite-first) — `Db.open(path)`,
/// `db.set<Person>`, change tracking, code-first migrations,
/// bulk operations, reactive queries. SQLite is the default
/// and the only storage engine shipped out of the box.
/// 5. Sync (offline-first) — `SyncProvider` interface, push/pull
/// pipeline, identity persistence, conflict resolution, retry
/// with exponential backoff, sync triggers.
/// 6. Realtime — WebSocket + SSE clients with codegen.
///
/// ## Status
///
/// `d_rocket` is at 1.2.0 (SQLite-First for Flutter).
/// All four data layers are complete: LINQ, Serializer, REST
/// (with wrap-around resilience + cancelable requests), ORM
/// (with bulk + reactive queries), Sync (offline-first with
/// conflict resolution), Realtime (WebSocket + SSE with codegen).
///
/// See `CHANGELOG.md` for the full history.
library;

// ─── Layer 3: LINQ-style queries ─────────────────────────────────────
export 'src/linq/linq.dart';
export 'src/linq/record.dart';

// ─── Layer 1: Serialization (absorbed from d_serializer 1.3.0) ──────
//
// This is the *runtime* of the serializer. The `d_rocket_builder`
// package emits the per-class `*.d_rocket_serializer.g.dart` parts
// and the central `d_rocket_registry.g.dart` (with `initializeD`)
// that calls `register<X>Serializer` for every `@Serializable`
// class — the user only has to call `initializeD` once.
export 'src/serializer/format.dart';
export 'src/serializer/json_key.dart';
export 'src/serializer/json_naming.dart';
export 'src/serializer/serializable.dart';
export 'src/serializer/serializable_union.dart';
export 'src/serializer/serializer.dart';
export 'src/serializer/unknown_key_policy.dart';

// ─── Layer 2: REST with steroids (absorbed from d_rest 0.1.0) ──────
//
// Runtime of the typed HTTP client generator. The `d_rocket_builder`
// package emits the per-class `*.d_rocket_rest_client.g.dart` parts
// and the central `d_rocket_registry.g.dart` (with `initializeD`)
// that calls `register<X>RestClient` for every `@RestClient`
// class. The runtime is byte-for-byte the same as `d_rest` 0.1.0
// — only the home changed.
export 'src/rest/cancel_token.dart';
export 'src/rest/clients/circuit_breaker_http_client.dart';
export 'src/rest/clients/rate_limited_http_client.dart';
export 'src/rest/clients/retrying_http_client.dart';
export 'src/rest/logging_interceptor.dart';
export 'src/rest/rest.dart';

// ─── Layer 4: ORM (SQLite-First,) ──────────────────────────
//
// The ORM ships with SQLite built-in. The user opens a database
// with `Db.open(path: ...)`, then `db.set<T>` for typed
// LINQ queries. Under the hood we have:
// * `SqliteQueryProvider` — the sqflite wrapper (implements
// the abstract `AsyncQueryProvider`).
// * `Queryable<T>` + `asQueryable` — the LINQ-style
// queryable, with `toListAsync_` / `firstOrDefaultAsync_` / etc.
// * `SqlTranslator` + `SqlFragment` — turns the
// Expr DSL into real SQL (SQLite dialect).
// * `DbContext` + `DbSet<T>` — the ORM core, with
// change tracking, migrations, bulk ops, watch.
//
// The `d_rocket_builder` package emits the per-class
// `*.d_rocket_orm.g.dart` parts and the central
// `d_rocket_registry.g.dart` (with `initializeD`) that calls
// `register<X>EntityMeta` for every `@Table` class.
// The runtime here ships the annotations, the
// `EntityMeta` / `ChangeTracker` / `DbSet<T>` /
// `DbContext` types, and the `EntityRegistry` global
// lookup.
export 'src/orm/orm.dart';

//: SQLite-First. The SQLite engine is bundled
// directly in `d_rocket`. No more `d_rocket_provider_sqlite`
// package to import — `Db.open(path: ...)` is all the
// user needs. The internal `SqliteQueryProvider` is exported
// for advanced use cases (e.g. sharing a DB between multiple
// `Db` instances).
export 'src/sqlite/db_context_extension.dart';
export 'src/sqlite/db_set_extension.dart';
export 'src/sqlite/encryption_config.dart';
export 'src/sqlite/fragment.dart';
export 'src/sqlite/key_provider.dart';
export 'src/sqlite/query_provider.dart';
export 'src/sqlite/queryable.dart';
export 'src/sqlite/db.dart';
export 'src/sqlite/redact_pragma_key.dart';
export 'src/sqlite/translator.dart';
export 'src/linq/operators/group_by.dart' show IGrouping;
export 'src/linq/operators/lookup.dart';

// ─── Layer 5: Sync (offline-first) ────────────────────────────────────
//
// The sync layer: `SyncProvider` interface,
// `SyncEnvelope` / `SyncChange` wire types, identity persistence
// (clientId + watermark), conflict resolution strategies
// (LWW + custom + merge strategies), sync triggers
// (periodic + signal + manual), and retry policies
// (exponential backoff + no-retry). `RestSyncProvider` is the
// HTTP+JSON implementation of `SyncProvider`.
//
// `shared_preferences_sync_state_store.dart` moved to
// `d_rocket_provider_flutter` in .
export 'src/sync/rest_sync_provider.dart';
export 'src/sync/sync.dart';

// ─── Layer 6: Realtime ─────────────────────────────────────
//
// WebSocket + SSE clients. The `d_rocket_builder` package emits the
// per-class `*.d_rocket_realtime.g.dart` parts and the
// central `d_rocket_registry.g.dart` (with `initializeD`) that
// calls `register<X>WebSocketClient` and `register<X>SseClient`
// for every `@WebSocketClient` and `@SseClient` class. The runtime
// here ships the raw `WebSocketConnection` / `SseConnection`
// interfaces + the `IOWebSocketClient` (dart:io) implementation.
export 'src/realtime/annotations.dart';
export 'src/realtime/sse.dart';
export 'src/realtime/websocket.dart';
