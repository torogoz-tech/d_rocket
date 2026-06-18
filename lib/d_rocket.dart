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
/// 4. ORM (engine-agnostic) — `DbContext` / `DbSet<T>` /
/// `@Table` / change tracking / code-first migrations /
/// auto-migrations. The actual database engine is a
/// separate `d_rocket_engine_*` package. `d_rocket` ships
/// the engine-agnostic core + the `EngineRegistry` slot.
/// To use a real database, add `d_rocket_engine_sqlite`
/// (or another engine) and call its `register()` once
/// at app startup.
/// 5. Sync (offline-first) — `SyncProvider` interface, push/pull
/// pipeline, identity persistence, conflict resolution, retry
/// with exponential backoff, sync triggers.
/// 6. Realtime — WebSocket + SSE clients with codegen.
///
/// ## Status
///
/// `d_rocket` is at 2.0.0 (engine-agnostic, lockstep
/// with the `d_rocket_engine_*` packages). All six
/// data layers are complete: LINQ, Serializer, REST
/// (with wrap-around resilience + cancelable requests),
/// ORM (engine-agnostic, three engines in 2.0: SQLite,
/// Postgres, libsql_wasm), Sync (offline-first with
/// conflict resolution), Realtime (WebSocket + SSE with
/// codegen).
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

// ─── Layer 4: ORM (engine-agnostic in 2.0) ────────────────
//
// In 2.0 the ORM core is engine-agnostic. The
// `Db` facade, `SqliteQueryProvider`,
// `Queryable<T>`, SQL `Fragment` / `Translator`,
// `EncryptionConfig`, and the LINQ-SQL
// `db.set<T>().where(...)` extensions all
// moved to a separate `d_rocket_engine_sqlite`
// package. Consumers add that package to their
// `pubspec.yaml` and call
// `d_rocket_engine_sqlite.register()` before
// `Db.open` / `Db.inMemory`.
//
// The runtime here ships the engine-agnostic
// ORM surface: the annotations (`@Table`,
// `@Column`, `@ForeignKey`, `@Index`), the
// `EntityMeta` / `ChangeTracker` / `DbSet<T>` /
// `DbContext` types, the migration primitives,
// the auto-migrator, the `EntityRegistry` global
// lookup, and the `EngineRegistry` (the slot
// where a `DbEngine` is plugged in).
//
// The `d_rocket_builder` package emits the per-
// class `*.d_rocket_orm.g.dart` parts and the
// central `d_rocket_registry.g.dart` (with
// `initializeD`) that calls
// `register<X>EntityMeta` for every `@Table`
// class.
export 'src/orm/orm.dart';
export 'src/orm/auto_migration/auto_migration.dart';

//: LINQ-to-collections (no engine required).
// `IQueryable<T>` / `IEnumerable<T>` / `Expr` /
// `EnumerableQuery` work over any `Iterable<T>`
// and don't need a database. The engine-specific
// SQL `Queryable<T>` and the `db.set<T>().where`
// extensions live in `d_rocket_engine_sqlite`.
export 'src/linq/operators/group_by.dart' show IGrouping;
export 'src/linq/operators/lookup.dart';

//: SQL infrastructure (engine-agnostic).
// `SqlFragment` is the unit of SQL emission: a
// SQL string + its bind parameters. Each
// engine's translator walks the in-memory
// `Expr` tree and produces a `SqlFragment`.
// The engine's `AsyncQueryProvider` executes
// the fragment; for engines that use a
// different placeholder convention (e.g.
// Postgres uses `$1, $2, ...`), the provider
// rewrites the `?` placeholders. This keeps
// the operator layer (where / select /
// orderBy / take / skip / groupBy / join) in
// d_rocket core; only the per-dialect
// translation bits live in the engine.
export 'src/linq/sql/sql_fragment.dart';

//: `redactPragmaKey` is the SQL redaction utility used by
// `LoggingInterceptor`. It lives in d_rocket core
// (engine-agnostic) even though `PRAGMA key` /
// `PRAGMA rekey` are SQLCipher statements; the
// function is a pure string transformation and is
// useful for any REST layer that needs to scrub
// keys out of SQL traces before logging.
export 'src/redact_pragma_key.dart';

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
export 'src/sync/conflict_policy.dart';
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
