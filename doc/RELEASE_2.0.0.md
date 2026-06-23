# Release notes — `d_rocket 2.0.0`

> **The current release.** This is the engine-agnostic
> multi-engine release. The `2.x` line ships a new minor on a
> monthly cadence — see
> [`RELEASE_CADENCE.md`](RELEASE_CADENCE.md) for the full
> policy.

The `2.0.0` line is the largest release of `d_rocket` since
the 1.0.0 rename. The ORM is decoupled from the engine, three
engines ship as separate packages, the lints are split into
their own package, and the realtime annotations are renamed to
match the EF Core / Spring convention. The total surface area
of public APIs grew by ~40% over `1.2.2`; the breaking changes
are listed below.

## Headline

- The ORM is now **engine-agnostic**. The same `DbContext`,
  `DbSet<T>`, LINQ chain, and `@Table` codegen runs on three
  shipped engines:
  - [`d_rocket_engine_sqlite`](https://pub.dev/packages/d_rocket_engine_sqlite)
    — `package:sqlite3` (file or `sqlite::memory:`; SQLCipher
    supported). Has both **sync and async** LINQ terminals.
  - [`d_rocket_engine_postgres`](https://pub.dev/packages/d_rocket_engine_postgres)
    — `package:postgres` (wire protocol, pure Dart, no FFI).
    **Async-only** LINQ.
  - [`d_rocket_engine_web`](https://pub.dev/packages/d_rocket_engine_web)
    — IndexedDB via `package:idb_shim` (browser). **Async-only**
    LINQ.
- A new **`EngineRegistry`** holds the active `DbEngine`. The
  shipped engines register themselves via the
  `dRocketSqlite()`, `dRocketPostgres()`, and `dRocketWeb()`
  helpers called once at app startup. New engines are
  pluggable through the same contract.
- **`d_rocket_lints`** is now a separate package implemented on
  top of `analysis_server_plugin`. The diagnostic codes are
  `d_rocket_untranslated_closure_linq` and
  `d_rocket_n_plus_one`.

## The 6 public packages (lockstep 2.0.0)

| Package | Version |
|---|---|
| `d_rocket` | `2.0.0` |
| `d_rocket_builder` | `2.0.0` |
| `d_rocket_lints` | `2.0.0` |
| `d_rocket_engine_sqlite` | `2.0.0` |
| `d_rocket_engine_postgres` | `2.0.0` |
| `d_rocket_engine_web` | `2.0.0` |

## What's new in 2.0.0

### ORM (Layer 4) — engine-agnostic

- The ORM core moved out of `d_rocket` into a new internal
  contract; the DB facade moved to the engine packages
  (`SqliteDb` / `PgDb` / `WebDb`).
- Each engine registers itself with a single call
  (`dRocketSqlite()` etc.). After that, every existing
  `DbContext` / `DbSet<T>` / LINQ chain works as before.
- The `EntityRegistry` is global and populated by
  `initializeD()` (the codegen output) so the auto-migrator
  can compute schema diffs without an explicit
  `entityMetas: [...]` argument to `Db.open()`.
- A new `DbInterceptor` chain lets you audit, soft-delete, or
  rewrite every entity-level event before it hits the DB.
- A new `redactPragmaKey` helper obfuscates the `PRAGMA key`
  value in SQL logs (SQLCipher support).
- The auto-migrator is rewritten on top of
  `pendingSchemaDiff()` (returns the diff) +
  `runAutoMigrations()` (applies the safe subset). The
  1.2.x `Db.open(entityMetas: [...], autoMigrate: true)`
  flow is gone.
- The migration CLI is split in two halves to keep the
  dependency graph acyclic:
  - `d_rocket:migration` (the scaffolder) keeps the
    `add` / `list` / `doctor` subcommands. Engine-agnostic.
    The `status` / `run` / `rollback` subcommands print a
    redirect message telling the user to add
    `d_rocket_engine_sqlite` and re-run via
    `dart run d_rocket_engine_sqlite:migration`.
  - `d_rocket_engine_sqlite:migration` (the runtime) ships
    in the engine package and handles the three subcommands
    that need a real SQLite engine. It depends on `d_rocket`
    (not the other way around).
  See [`11-cli.md`](11-cli.md#migration-cli) for the full
  rationale.

### Sync (Layer 5)

- `RestSyncProvider` is stable; the conflict-policy hierarchy
  is now a sealed class with `LwwConflictPolicy`,
  `ClientWinsConflictPolicy`, and `CustomConflictPolicy`.
- `SyncProgress` and `SyncMetrics` add structured observability
  (per-phase counters, last-error, retry count).
- `AuthRefreshSync` auto-refreshes OAuth2 access tokens
  between push and pull cycles.
- `ConnectivityProvider` gates push/pull on online/offline
  detection.
- `MultiTenantSync` keeps a per-tenant identity and queue.

### Realtime (Layer 6)

- The 1.x `@WebSocketRoute` / `@SseRoute` annotations are
  renamed to `@WebSocketClient` / `@SseClient` to match the
  EF Core / Spring naming convention. The 1.x names are kept
  as typedefs for 1.x source compatibility.
- The new `WebWebSocketClient` is the browser impl; the
  existing `IOWebSocketClient` is the `dart:io` impl.
- `WebSocketReconnector` adds exponential backoff + heartbeat
  to the existing reconnect loop.

### Lints (new package)

- `d_rocket_lints` is the new home of the two custom lints
  (`d_rocket_untranslated_closure_linq` and
  `d_rocket_n_plus_one`). It is implemented on
  `analysis_server_plugin` and is auto-discovered by
  `dart analyze` once the plugin is listed in
  `analysis_options.yaml`.
- The 1.x class names (`LinqClosureRule`, `NPlusOneRule`) are
  kept as typedefs in `d_rocket_lints` for source
  compatibility, but the analyzer uses the diagnostic codes
  above.

### Codegen

- 7 builders, one per concern:
  `record`, `serializer`, `rest_client`, `rocket_table`,
  `rocket_migration`, `realtime`, `record_registry`.
- All builder ids use the `d_rocket_builder:*` namespace.
  The 1.x `d_rocket:*` names are kept as typedefs for source
  compatibility.
- The `d_rocket_builder:rocket_migration` builder is new; it
  reads the `@Migration` top-level function and emits a
  `MigrationBase` subclass with `up()` / `down()`.
- The `d_rocket_builder:record` builder is new; it scans for
  `extends Record` and emits `_<X>Init` + `register<X>Record`.

## Breaking changes from 1.2.2

| Change | Migration |
|---|---|
| `d_rocket 2.0.0` does **not** register a default engine. You must call `dRocketSqlite()` / `dRocketPostgres()` / `dRocketWeb()` once at app startup before any `Db.open(...)`. | Add the engine package to `pubspec.yaml` and call its helper. |
| `Db.open(entityMetas: [...], autoMigrate: true)` is removed. | Use `db.pendingSchemaDiff()` + `db.runAutoMigrations()`. |
| The lints moved to `d_rocket_lints` and the `custom_lint` setup is replaced by `analysis_server_plugin`. | Add `d_rocket_lints: ^2.0.0` to `dev_dependencies` and list `d_rocket_lints` in `analysis_options.yaml`. |
| `@WebSocketRoute` → `@WebSocketClient`, `@SseRoute` → `@SseClient`. | Rename the annotations; the codegen output suffix does not change. |
| `LinqClosureRule` and `NPlusOneRule` are typedefs only; the analyzer emits `d_rocket_untranslated_closure_linq` and `d_rocket_n_plus_one` as codes. | Update any rule-key strings in CI scripts or linter configurations. |
| `RocketDbContext` → `DbContext` (1.0.0 already did this rename; final cleanup of the 1.0 era typedefs is in 2.0.0). | If you used the old name, rename. |
| The `package:libsql` / WASM engine that was discussed in 1.x planning notes is **not** shipped in 2.0.0. The web target is IndexedDB via `d_rocket_engine_web`. | Use `d_rocket_engine_web` for browser persistence. |
| `LegacySyncQueryProvider` is the only sync LINQ provider; only the SQLite engine implements it. Postgres and Web are async-only. | Use `*Async_` terminals on Postgres and Web. |

For the full per-section migration recipe, see
[`11-migration-1-x-to-2-0.md`](11-migration-1-x-to-2-0.md).

## Test counts at 2.0.0

| Suite | Tests | Status |
|---|---|---|
| `d_rocket` (core) | ~1,184 | ✅ all pass |
| `d_rocket_lints` (2 rules) | n/a (linter is run on the d_rocket source) | ✅ 0 violations |
| `d_rocket_engine_sqlite` (SQLite parity) | 1,184 — same suite, SQLite backend | ✅ |
| `d_rocket_engine_postgres` (Postgres parity) | 18 | ✅ (Postgres server required) |
| `d_rocket_engine_web` (IndexedDB parity) | smoke | ✅ |
| `d_rocket_builder` (codegen) | n/a (codegen output is checked into the source tree) | ✅ 0 drift |

The Postgres test suite is skip-gated on a running Postgres
server (set the `D_ROCKET_POSTGRES_TEST_URL` env var to
opt in). Without a server, the suite reports `0 pass + 18
skip` and the CI stays green.

## What's in the public barrel

The 6 layers and their public surface are listed in the
[`README.md`](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/README.md).
The per-layer reference is in
[`doc/04-layer-1-serialization.md`](04-layer-1-serialization.md)
through
[`doc/09-layer-6-realtime.md`](09-layer-6-realtime.md).

## Codegen output format

The codegen output suffixes (`.d_rocket_serializer.g.dart`,
`.d_rocket_rest_client.g.dart`, `.d_rocket_orm.g.dart`) are
unchanged from 1.2.x. A 1.x project that has been building
successfully will continue to build with `2.0.0` once the
engine registration helper is added.

## Release cadence

`d_rocket 2.1.0` will ship on the first Tuesday of next month.
Bug fixes can ship at any time as patch releases. See
[`RELEASE_CADENCE.md`](RELEASE_CADENCE.md) for the full policy
and the next scheduled release date.

## Thanks

To every contributor and early adopter of `d_rocket 1.x` and
the legacy `d_serializer` / `d_rest` / `d_builder` packages.
The 2.0.0 release is the first where the engine-agnostic
architecture is public; it could not have happened without the
production feedback from the 1.x line.

`d_rocket 2.0.0` is the new home on the `2.x` line. Welcome.
