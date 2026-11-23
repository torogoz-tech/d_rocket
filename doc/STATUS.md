# d_rocket — Status

> One-page snapshot of where the framework is today. If you are
> evaluating d_rocket, this is the page to read.

## Where we are

| Metric | Value |
|---|---|
| Current line | **2.6.0** (local release candidate; not pushed) |
| Previous release | 2.5.0 |
| Test suite | 900 `d_rocket` tests and 74 `d_rocket_builder` tests pass locally; platform validation was also performed manually |
| Analyzer warnings | 0 |
| Package versions | core/builder/SQLite `2.6.0`; Flutter bindings and lints advance independently |
| Release policy | core and builder are coordinated; bindings, lints and engines advance independently when their APIs require it |
| Source | `github.com/torogoz-tech/d_rocket` |
| pub.dev | `pub.dev/packages/d_rocket` and compatible package families |

## What d_rocket is (one-liner per layer)

1. **Serialization** — `@Serializable` with `fromJson` / `toJson`, `JsonNaming`, sealed unions via `@SerializableUnion`, per-property formatters, three `unknownKeyPolicy` modes.
2. **REST** — `@RestClient` with retry, rate limit, circuit breaker, response cache, interceptor chain.
3. **LINQ** — deferred `IQueryable<T>` with 35+ operators, push-down to SQL on `DbSet<T>` (sync on SQLite, async everywhere).
4. **ORM (engine-agnostic)** — `DbContext` + `DbSet<T>` with change tracking, code-first `@Migration`, auto-migrator with `pendingSchemaDiff()`, eager-loading `include_<TNav>()`, reactive `watch()`, `DbInterceptor` chain, `redactPragmaKey`.
5. **Sync** — `SyncProvider` + `RestSyncProvider` + persistent identity + push / pull + pluggable conflict resolution.
6. **Realtime** — `@WebSocketClient` + `@SseClient` codegen → typed `Stream<T>` with reconnect + backoff + heartbeat.
7. **Forms** — `@Form` model adapters with typed bindings, synchronous/asynchronous validation, debounce, composite values and REST field errors.

## Releases at a glance

### 2.6.0 — reactive REST data and generated value models

- Reactive in-memory REST queries with in-flight deduplication, tag
  invalidation and instance-scoped cache ownership.
- Opt-in generated `copyWith`, equality and JSON Schema metadata.
- Explicit serializer converters and `@JsonKey(readValue: ...)` support.
- Nested form groups, field arrays, composite bindings and REST validation
  diagnostics.
- Realtime delivery queues, channel multiplexing, attachment checkpoints,
  pagination, multipart and OpenAPI metadata improvements.

This version is prepared in local commits only; no push or publication has
been performed.

### 2.5.0 — forms, serialization and realtime hardening

- Asynchronous form validators, validation states, debounce and direct REST
  validation error mapping.
- Detailed generated serialization failures through `SerializationException`.
- UUID validation with optional version restrictions from v1 through v8.
- Dynamic WebSocket authentication headers, bounded reconnection, lifecycle
  states, heartbeat-aware inactivity detection and correlated diagnostics.
- Compatibility workflow for Dart 3.11.5, 3.12.0 and 3.13.0, plus manual
  validation on Web, Android, iOS, macOS and Linux.

This version is prepared in local commits only; no push or publication has
been performed.

### 2.4.0–2.4.2 — transport and generic codegen hardening

- Shared transport policies, owned SSE transport shutdown and generic registry
  fixes for external models and opaque `Object?` payloads.

### 2.2.0–2.3.0 — forms and enum contracts

- Model-driven forms, generic/composite bindings and field validation shipped
  in 2.2.0.
- Enum contracts were aligned across JSON, forms, REST and SQLite persistence
  in 2.3.0, including explicit unknown-value policies.

### 2.1.0 — production-readiness consolidation

- Codegen preserves nullability and rejects implicit exact-decimal storage.
- SQLite LINQ, migrations and the migration CLI have regression and smoke
  coverage.
- Sync has explicit retry/idempotency documentation and stable change keys.
- WebSocket/SSE reconnect behavior and the Flutter DevTools diagnostics flow
  are documented and covered by tests.
- `d_rocket_engine_mobile` provides the `connectivity_plus` adapter for
  Flutter applications.

### 2.0.0 — engine-agnostic multi-engine

- **Engine split.** The ORM core is engine-agnostic. The DB facade
  moved to separate packages:
  - `d_rocket_engine_sqlite` — `package:sqlite3` (file + `sqlite::memory:`)
  - `d_rocket_engine_postgres` — `package:postgres` (wire protocol; pure Dart, no FFI)
  - `d_rocket_engine_web` — IndexedDB via `idb_shim` (browser)
- **`EngineRegistry`** holds the active `DbEngine`. Call
  `dRocketSqlite()` / `dRocketPostgres()` / `dRocketWeb()` once at
  app startup; then `Db.open(...)`, `PgDb.open(...)`, or
  `WebDb.open(...)` respectively.
- **`@LintsPlugin` split.** `d_rocket_lints` is a standalone
  package using `analysis_server_plugin` (the new `custom_lint`
  predecessor). Rule codes: `d_rocket_untranslated_closure_linq`,
  `d_rocket_n_plus_one`.
- **Auto-migrator rewrite.** The 1.2.0 `Db.open(entityMetas: [...],
  autoMigrate: true)` flow is gone. The 2.0.0 flow:
  `db.pendingSchemaDiff()` returns the diff; safe changes (CREATE
  TABLE, ADD COLUMN) apply via `db.runAutoMigrations()`; unsafe
  changes (DROP, MODIFY) require a hand-written `@Migration`.
- **Realtime rename.** `@WebSocketRoute` / `@SseRoute` → `@WebSocketClient` /
  `@SseClient` (matches EF Core / Spring style; the previous names
  were kept as typedefs for 1.x source compatibility).

### 1.2.2 — last 1.x release

- Codegen: fixed `analyzer` constraint so consumers can bump.
- Doc: 1.x → 2.0 migration guide published.

### 1.2.0 — auto-migrations (deprecated by 2.0.0)

- The 1.2.0 `Db.open(entityMetas: [...], autoMigrate: true)` API
  was removed in 2.0.0 (replaced by `db.runAutoMigrations()`).

### 1.1.0 (and earlier)

- The 1.0 rename (drop `Rocket` prefix from every public type and
  CLI command name).
- The four legacy packages (`d_serializer`, `d_rest`,
  `d_serializer_builder`, `d_rest_build`) marked deprecated and
  the migration path documented.

## Roadmap (post-2.6.0 candidates)

| Feature | Status | Notes |
|---|---|---|
| `d_rocket_engine_libsql_wasm` | not started | dropped in 2.0.0 (the web engine uses IndexedDB instead). |
| `d_rocket_admin` (DB console UI) | not started | Would be a Flutter web app on top of the engine. |
| Codegen using `package:macros` | not started | Requires analyzer ^13; we're on ^10 today. |
| Form binding | shipped | `@Form` shipped in 2.2.0; asynchronous validation and REST mapping are in 2.5.0. |
| Postgres/Web parity | partial | SQLite is the reference engine; broader parity tests remain future work. |
| Benchmarks vs Drift / EF Core / Hibernate | partial | Cross-engine comparison is not built. |

## Where to read more

- [README](https://github.com/torogoz-tech/d_rocket/blob/main/README.md) — landing page, 7-layer overview.
- [CHANGELOG](https://github.com/torogoz-tech/d_rocket/blob/main/CHANGELOG.md) — every release.
- [ROADMAP](https://github.com/torogoz-tech/d_rocket/blob/main/doc/ROADMAP.md) — historical phases + post-2.0 candidates.
- [BUG_REVIEW](https://github.com/torogoz-tech/d_rocket/blob/main/doc/BUG_REVIEW.md) — bugs found and fixed (1 through B-09, all closed as of 1.2.1; B-21/22/23/24/25/27/28 fixed at 2.0.0).
- [FAQ](https://github.com/torogoz-tech/d_rocket/blob/main/doc/13-faq.md) — common questions.
- [doc/](https://github.com/torogoz-tech/d_rocket/tree/main/doc/) — the full reference (overview, quickstart, installation, 7 layer guides, migrations, CLI, cookbook, FAQ, architecture).
