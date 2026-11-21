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
seven concerns that, in most stacks, force you to glue together half
a dozen different libraries: **JSON serialization**, **typed HTTP
clients**, **LINQ-style queries**, **an ORM**, **offline-first sync**,
and **WebSocket / SSE realtime**.

## Modular by design

The framework is built as **seven independent layers**. A single
import — `package:d_rocket/d_rocket.dart` — exposes them all,
but **only the code you use is in your final app**:

- A Flutter app that just needs typed JSON ↔ Dart picks the
  `Serializer` API and ships with **Layer 1 only** (≈ 60 KB).
- A pure REST client picks `@RestClient` (Layer 2) and ships
  with **Layer 2 only** (≈ 110 KB), without pulling in LINQ,
  the ORM, sync, or realtime.
- A client with an HTTP API + offline cache + push notifications
  picks **Layers 2 + 4 + 6** and ships just those (≈ 290 KB).
- A full backend client that uses **all seven** ships the whole
  package (≈ 530 KB pre-tree-shake).

There is no global state, no `main()`-time side effects, no
implicit registration. The codegen emits only the `fromJson` /
`toJson` / `RestClient` impl / `EntityMeta` / typed stream
for the classes you actually annotated. Lint rules, the engine
adapter, and the DB facade are separate dev_dependencies that
don't bloat the runtime.

> The corollary: **you can adopt d_rocket one layer at a time**.
> Start with `@Serializable` for JSON. Later add `@RestClient`.
> Later add the ORM. The migration is per-class, not
> project-wide.

## The seven layers

| # | Layer | Highlights | Doc |
|---|---|---|---|
| 1 | **Serialization** | `@Serializable` → `fromJson` / `toJson`; `@SerializableUnion`; `@JsonKey` + `JsonNaming`; `JsonFactory` / `JsonEncoder`; `CodecEncoder` (json, msgpack, cbor, bson, xml, url-form, multipart, raw); `SerializerSnapshot`. | [04](https://github.com/torogoz-tech/d_rocket/blob/main/doc/04-layer-1-serialization.md) |
| 2 | **REST** | `@RestClient` + 6 verbs + 7 parameter annotations; **7 wrap-around clients** — `HttpCache`, `GzipCodec`, `HmacSha256Signer`, `OAuth2HttpClient`, `RateLimitedHttpClient`, `RetryingHttpClient`, `CircuitBreakerHttpClient`; streaming; `CancelToken`; `LoggingInterceptor`. | [05](https://github.com/torogoz-tech/d_rocket/blob/main/doc/05-layer-2-rest.md) |
| 3 | **LINQ** | Deferred `Queryable<T>` with **35+ operators** (filter, project, order, page, group, join, aggregate, set, quantifier, element, convert). Engine-agnostic `Expr` AST. Sync `*_` + async `*Async_` terminals. | [06](https://github.com/torogoz-tech/d_rocket/blob/main/doc/06-layer-3-linq.md) |
| 4 | **ORM** | `DbContext` + change-tracked `DbSet<T>` (`add` / `markModified` / `remove` + `saveChanges`); `include_<TNav>()`; `watch()`; `DbInterceptor` chain; `@Migration` + auto-migrator (`pendingSchemaDiff()` / `runAutoMigrations()`); bulk ops. | [07](https://github.com/torogoz-tech/d_rocket/blob/main/doc/07-layer-4-orm.md) |
| 5 | **Sync** | `SyncProvider` (sealed) — `RestSyncProvider`, `WebSocketSyncProvider`, `MultiTransportSyncProvider`; persistent identity; push + pull; **conflict resolution** (`Lww`, `ClientWins`, `Custom`, `MergeStrategies`); 4 retry policies; 3 `SyncStateStore` impls; `ConnectivityProvider`; `MultiTenantSync`; `AuthRefreshSync`; `VectorClock`. | [08](https://github.com/torogoz-tech/d_rocket/blob/main/doc/08-layer-5-sync.md) |
| 6 | **Realtime** | `@WebSocketClient` + `@SseClient` → typed `Stream<T>`; `IOWebSocketClient` (dart:io) + `WebWebSocketClient` (browser); controlled `WebSocketReconnector` and `SseReconnector` with backoff, dynamic auth headers, heartbeats and resumable cursors. | [09](https://github.com/torogoz-tech/d_rocket/blob/main/doc/09-layer-6-realtime.md) |
| 7 | **Forms** | `@Form` → `<ModelName>Form`; generic `bind()` / `bindRaw()`, model validation, typed conversion, observable field changes, stable errors and safe construction for Flutter or Dart controls. | [2.2](https://github.com/torogoz-tech/d_rocket/blob/main/doc/RELEASE_2.2.0.md) |

Forms are the seventh framework layer, available since 2.2.0. They bind
existing Flutter or Dart controls to an annotated model without introducing
framework widgets or a parallel form model. See
[`RELEASE_2.2.0.md`](doc/RELEASE_2.2.0.md) and
[`2.2-formularios-modelo.md`](doc/2.2-formularios-modelo.md).

UUID fields can use the dedicated validator instead of repeating a regular
expression:

```dart
@Form()
class RequestModel {
  RequestModel({required this.requestId});

  @Required()
  @Uuid(version: UuidVersion.v4)
  final String requestId;
}
```

`@Uuid()` accepts supported UUID versions, while `version` restricts the
field to one version. Validation is separate from UUID generation through
`generateUuidV4()`.

For Flutter applications, the optional [`d_rocket_flutter`](https://pub.dev/packages/d_rocket_flutter)
package provides `DrocketFormBuilder` and generic field bindings. It does not
replace `TextField`, `DropdownButton` or any other control: the application
passes each control's existing callback to `onChanged`, `onChangedNullable` or
`onChangedRaw` and reads `errorText` from the same model field state.

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
| [`d_rocket_engine_mobile`](https://pub.dev/packages/d_rocket_engine_mobile) | Flutter mobile connectivity via `connectivity_plus` | connectivity adapter |

> The engine-agnostic LINQ is provided by `d_rocket` core. Each
> engine supplies a `QueryProvider` and a `SqlDialect` so the
> in-memory `Expr` tree is translated to the engine's SQL dialect.

## Install

Pick the layers you need. There is no single "all-in" config.

```yaml
# Layer 1 only (JSON ↔ Dart):
dependencies:
  d_rocket: ^2.4.0

# Layer 1 + 2 (typed HTTP client):
dependencies:
  d_rocket: ^2.4.0
dev_dependencies:
  d_rocket_builder: ^2.4.0
  build_runner: ^2.4.13

# Layers 1, 2, 4, 6 (HTTP + ORM + realtime):
dependencies:
  d_rocket: ^2.4.0
  d_rocket_engine_sqlite: ^2.1.0   # Compatible with core 2.4.0
dev_dependencies:
  d_rocket_builder: ^2.4.0
  d_rocket_lints: ^2.3.0            # N+1 + closure-linq + enum guidance
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

# Acknowledge destructive operations explicitly when reviewed (optional)
dart run d_rocket:migration add drop_legacy_events \
  --db app.db --entities lib/db/entities.dart --include-unsafe

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

The complete 2.1.0 production flow, including SQLite, sync, connectivity,
migrations and DevTools, is documented in
[`doc/2.1-production-example.md`](doc/2.1-production-example.md).

The 2.2.0 model-driven forms contract, including Flutter bindings, raw input
conversion, validation modes, JSON/REST integration and non-nullable handling,
is documented in [`doc/RELEASE_2.2.0.md`](doc/RELEASE_2.2.0.md).

The 2.2.4 SSE transport contract, including direct `HttpSseClient`
configuration, interceptors, connection timeout, content-type validation,
dynamic headers, authentication recovery, lifecycle states, manual cursor
acknowledgement, heartbeat-aware inactivity and complete transport shutdown,
is documented in [`doc/2.2.2-sse-reconnect.md`](doc/2.2.2-sse-reconnect.md).

The 2.4.0 integration contract is documented in
[`doc/RELEASE_2.4.0.md`](doc/RELEASE_2.4.0.md). It covers shared transport
policies for REST, SSE and downloads, contextual retries, configurable
diagnostic redaction, explicit SSE transport ownership, generated generic
serializer registrations and the optional `d_rocket_flutter` bindings.

For Flutter applications, install the optional adapter alongside the core:

```yaml
dependencies:
  d_rocket: ^2.4.0
  d_rocket_flutter: ^2.4.0
```

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Torogoz Tech.

## Author

**Abner Velasco** — *Arquitecto de Soluciones*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Abner%20Velasco-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abnervelasco/)
