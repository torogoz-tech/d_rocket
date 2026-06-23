# d_rocket

> Dart's data rocket — serialize, query, persist, sync.

<p align="center">
  <img src="assets/banner.png" alt="d_rocket banner" width="100%">
</p>

[![ci](https://github.com/torogoz-tech/d_rocket/actions/workflows/ci.yml/badge.svg)](https://github.com/torogoz-tech/d_rocket/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/torogoz-tech/d_rocket/branch/main/graph/badge.svg)](https://codecov.io/gh/torogoz-tech/d_rocket)
[![license](https://img.shields.io/github/license/torogoz-tech/d_rocket)](LICENSE)

**d_rocket** is the engine-agnostic core of a single-package framework
for the data layer of Dart and Flutter applications. It unifies the
six concerns that, in most stacks, force you to glue together half
a dozen different libraries: **JSON serialization**, **typed HTTP
clients**, **LINQ-style queries**, **an ORM**, **offline-first sync**,
and **WebSocket / SSE realtime**.

## Modular by design

The framework is built as **six independent layers**. A single
package import — `package:d_rocket/d_rocket.dart` — exposes
them all, but **only the code you use is in your final app**:

- A Flutter app that just needs typed JSON ↔ Dart picks the
  `Serializer` API and ships with **Layer 1 only** (≈ 60 KB).
- A pure REST client picks **`@RestClient`** (Layer 2) and ships
  with **Layer 2 only** (≈ 110 KB), without pulling in LINQ,
  the ORM, sync, or realtime.
- A client with an HTTP API + offline cache + push notifications
  picks **Layers 2 + 4 + 6** and ships just those (≈ 290 KB).
- A full backend client that uses **all six** ships the whole
  package (≈ 530 KB pre-tree-shake, much less after).

There is no global state, no `main()`-time side effects, no
implicit registration. The codegen emits only the `fromJson` /
`toJson` / `RestClient` impl / `EntityMeta` / typed stream
for the classes you actually annotated. Lint rules, the engine
adapter, and the DB facade are separate dev_dependencies that
don't bloat the runtime.

> The corollary: **you can adopt d_rocket one layer at a time**.
> Start with `@Serializable` for JSON. Later, add `@RestClient`.
> Later, add the ORM. The migration is per-class, not
> project-wide.

## The six layers

| # | Layer | Features | Doc |
|---|---|---|---|
| 1 | **Serialization** | `@Serializable` → `fromJson` / `toJson`; `@SerializableUnion`; `@JsonKey` + `JsonNaming`; `unknownKeyPolicy`; `JsonFactory`; `JsonEncoder`; `CodecEncoder` (json, msgpack, cbor, bson, xml, url-form, multipart, raw); `SerializerSnapshot` for debug / diff / audit. | [04](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/04-layer-1-serialization.md) |
| 2 | **REST** | `@RestClient` + `@HttpGet`/`@Post`/`@Put`/`@Patch`/`@Delete`/`@Head`; `@Path`/`@Query`/`@Header`/`@Body`/`@Field`/`@Part`/`@RawBody`; **7 wrap-around clients** — `HttpCache` (response cache), `GzipCodec` (compression), `HmacSha256Signer` (HMAC signing), `OAuth2HttpClient` (auto-refresh tokens), `RateLimitedHttpClient` (token-bucket), `RetryingHttpClient` (exponential backoff), `CircuitBreakerHttpClient` (closed/open/half-open with `CircuitState` and `CircuitOpenException`); streaming `Stream<T>`; `CancelToken`; `LoggingInterceptor`. | [05](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/05-layer-2-rest.md) |
| 3 | **LINQ** | Deferred `Queryable<T>` with **35+ operators** — filter, project, order, page, group, join, aggregate, set, quantifier, element, convert. Engine-agnostic `Expr` AST with 17 node types. Sync `*_` + async `*Async_` terminals. Custom `SqlDialect` per engine. | [06](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/06-layer-3-linq.md) |
| 4 | **ORM** | `DbContext` + change-tracked `DbSet<T>` with `add` / `markModified` / `remove` + `saveChanges`; direct `insertOneAsync` / `updateOneAsync` / `deleteOneAsync`; `asQueryable`; `include_<TNav>()` eager-loading; reactive `watch()`; bulk operations; **`DbInterceptor`** chain (tenant filter, audit log, soft delete); `@Migration` + `MigrationBase`; **auto-migrator** with `pendingSchemaDiff()` + `runAutoMigrations()`; `EntityMeta` / `ColumnMeta` / `NavigationMeta` codegen output; `@Embedded` value objects; `InheritanceStrategy` + `OnDeleteAction`. | [07](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/07-layer-4-orm.md) |
| 5 | **Sync** | `SyncProvider` (sealed) + `RestSyncProvider` + `WebSocketSyncProvider` + `MultiTransportSyncProvider`; persistent identity (survives process restarts); push + pull pipelines; **conflict resolution** — `LwwConflictPolicy`, `ClientWinsConflictPolicy`, `CustomConflictPolicy` + `MergeStrategies`; triggers (periodic / signal / manual); retry — `ExponentialBackoffRetryPolicy`, `LinearBackoffRetryPolicy`, `FibonacciBackoffRetryPolicy`, `DecorrelatedJitterRetryPolicy`; 3 `SyncStateStore` impls; `SyncQueueStore`; `SyncProgress` + `SyncMetrics`; `SyncFilter`; `SyncSchema` versioning; `AuthRefreshSync`; `ConnectivityProvider`; `MultiTenantSync`; `SyncPriority` + `VectorClock`. | [08](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/08-layer-5-sync.md) |
| 6 | **Realtime** | `@WebSocketClient` + `@SseClient` codegen → typed `Stream<T>`; `IOWebSocketClient` (dart:io) + `WebWebSocketClient` (browser); `WebSocketReconnector` with exponential backoff + heartbeat; `WebSocketConnection` / `SseConnection` interfaces; `SseEvent` typed payloads. | [09](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/09-layer-6-realtime.md) |

A single `initializeD()` call (emitted by `d_rocket_builder` into
`d_rocket_registry.g.dart`) wires every annotated class in your
project. There is no per-file `registerAll()`.

## Engine adapters

The DB engine is a separate package. The same `DbContext` /
`DbSet<T>` / LINQ code runs on:

| Engine | Backend | LINQ |
|---|---|---|
| [`d_rocket_engine_sqlite`](https://pub.dev/packages/d_rocket_engine_sqlite) | `package:sqlite3` (file or `sqlite::memory:`; SQLCipher supported) | sync + async |
| [`d_rocket_engine_postgres`](https://pub.dev/packages/d_rocket_engine_postgres) | `package:postgres` (wire protocol; pure Dart, no FFI) | async only |
| [`d_rocket_engine_web`](https://pub.dev/packages/d_rocket_engine_web) | IndexedDB via `idb_shim` (browser) | async only |

> The engine-agnostic LINQ is provided by `d_rocket` core. Each
> engine supplies a `QueryProvider` and a `SqlDialect` so the
> in-memory `Expr` tree is translated to the engine's SQL dialect.

## Install

Pick the layers you need. There is no single "all-in" config.

```yaml
# Layer 1 only (JSON ↔ Dart):
dependencies:
  d_rocket: ^2.0.0

# Layer 1 + 2 (typed HTTP client):
dependencies:
  d_rocket: ^2.0.0
dev_dependencies:
  d_rocket_builder: ^2.0.0
  build_runner: ^2.4.13

# Layers 1, 2, 4, 6 (HTTP + ORM + realtime):
dependencies:
  d_rocket: ^2.0.0
  d_rocket_engine_sqlite: ^2.0.0   # or postgres / web
dev_dependencies:
  d_rocket_builder: ^2.0.0
  d_rocket_lints: ^2.0.0            # N+1 + closure-linq lints
  build_runner: ^2.4.13
```

## Code generation

`d_rocket_builder` runs under `build_runner` and emits 7 builders,
one per concern:

| Builder | Reads | Emits |
|---|---|---|
| `d_rocket_builder:record` | `extends Record` | `_<Name>Init` + `register<X>Record` |
| `d_rocket_builder:serializer` | `@Serializable` / `@SerializableUnion` | `fromJson` / `toJson` + `register<X>Serializer` |
| `d_rocket_builder:rest_client` | `@RestClient` | per-interface impl with interceptors, retry, serialization |
| `d_rocket_builder:rocket_table` | `@Table` + `@Column` + `@PrimaryKey` + `@ForeignKey` + `@Index` + `@Embedded` | `EntityMeta` |
| `d_rocket_builder:rocket_migration` | `@Migration` top-level function | `_$_<fnName> extends MigrationBase` |
| `d_rocket_builder:realtime` | `@WebSocketClient` / `@SseClient` | per-interface typed `Stream<T>` client |
| `d_rocket_builder:record_registry` | the union of all the above | `d_rocket_registry.g.dart` with `initializeD()` |

```bash
dart run build_runner build --delete-conflicting-outputs
```

## CLI

```bash
# Scaffold a migration from a pending schema diff
dart run d_rocket:migration add add_note_to_patients \
  --db app.db --entities lib/db/entities.dart

# Auto-rewrite LINQ closures to Expr.lambda
dart run d_rocket:closure transform-file lib/services/order_query.dart

# Run the analyzer with d_rocket lints (N+1 + closure-linq)
dart analyze
```

## Documentation

Full documentation lives in the
[monorepo README](https://github.com/torogoz-tech/d_rocket#readme)
and in the
[docs/](https://github.com/torogoz-tech/d_rocket/tree/main/doc)
directory (one `.md` per layer, plus installation, migrations,
cookbook, FAQ, and architecture). The package targets
**Dart 3.6+** and **Flutter 3.10+**.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Torogoz Tech.

## Author

**Abner Velasco** — *Arquitecto de Soluciones*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Abner%20Velasco-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abnervelasco/)
