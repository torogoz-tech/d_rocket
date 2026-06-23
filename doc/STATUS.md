# d_rocket — Status

> One-page snapshot of where the framework is today. If you are
> evaluating d_rocket, this is the page to read.

## Where we are

| Metric | Value |
|---|---|
| Latest release | **2.0.0** (engine-agnostic multi-engine) |
| Previous release | 1.2.2 |
| Test suite | ~1,184 pass across 6 packages (Postgres tests skip-gated) |
| Analyzer warnings | 0 |
| Public packages | `d_rocket`, `d_rocket_builder`, `d_rocket_lints`, `d_rocket_engine_sqlite`, `d_rocket_engine_postgres`, `d_rocket_engine_web` (lockstep since 2.0.0) |
| Lockstep versioning | yes — every release publishes all 6 packages at the same version on the same tag |
| Source | `github.com/torogoz-tech/d_rocket` |
| pub.dev | `pub.dev/packages/d_rocket` (and 5 siblings) |

## What d_rocket is (one-liner per layer)

1. **Serialization** — `@Serializable` with `fromJson` / `toJson`, `JsonNaming`, sealed unions via `@SerializableUnion`, per-property formatters, three `unknownKeyPolicy` modes.
2. **REST** — `@RestClient` with retry, rate limit, circuit breaker, response cache, interceptor chain.
3. **LINQ** — deferred `IQueryable<T>` with 35+ operators, push-down to SQL on `DbSet<T>` (sync on SQLite, async everywhere).
4. **ORM (engine-agnostic)** — `DbContext` + `DbSet<T>` with change tracking, code-first `@Migration`, auto-migrator with `pendingSchemaDiff()`, eager-loading `include_<TNav>()`, reactive `watch()`, `DbInterceptor` chain, `redactPragmaKey`.
5. **Sync** — `SyncProvider` + `RestSyncProvider` + persistent identity + push / pull + pluggable conflict resolution.
6. **Realtime** — `@WebSocketClient` + `@SseClient` codegen → typed `Stream<T>` with reconnect + backoff + heartbeat.

## Releases at a glance

### 2.0.0 — engine-agnostic multi-engine (current)

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

## Roadmap (post-2.0.0 candidates)

| Feature | Status | Notes |
|---|---|---|
| `d_rocket_engine_libsql_wasm` | not started | dropped in 2.0.0 (the web engine uses IndexedDB instead). |
| `d_rocket_admin` (DB console UI) | not started | Would be a Flutter web app on top of the engine. |
| Codegen using `package:macros` | not started | Requires analyzer ^13; we're on ^10 today. |
| Form binding (`@RocketForm`) | not started | Cross-cutting concern; deferred. |
| Benchmarks vs the EF Core / Hibernate | partial | One SQLite benchmark exists; cross-engine comparison not built. |

## Where to read more

- [README](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/README.md) — landing page, 6-layer overview.
- [CHANGELOG](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/CHANGELOG.md) — every release.
- [ROADMAP](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/ROADMAP.md) — historical phases + post-2.0 candidates.
- [BUG_REVIEW](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/BUG_REVIEW.md) — bugs found and fixed (1 through B-09, all closed as of 1.2.1; B-21/22/23/24/25/27/28 fixed at 2.0.0).
- [FAQ](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/13-faq.md) — common questions.
- [doc/](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/) — the full reference (overview, quickstart, installation, 6 layer guides, migrations, CLI, cookbook, FAQ, architecture).
