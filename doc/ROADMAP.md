# d_rocket — Roadmap

> What shipped in 1.x and 2.0.0, and what is on the
> post-2.0.0 roadmap. The 2.x line is the current line; the
> 1.x line is in maintenance mode.

---

## Where we are

| | |
|---|---|
| Latest release | **2.0.0** (engine-agnostic multi-engine) |
| Previous release | 1.2.2 (auto-migrations, 1.x maintenance) |
| Test suite | ~1,184 pass across 6 packages (Postgres tests skip-gated) |
| Analyzer warnings | 0 |
| Public packages | `d_rocket`, `d_rocket_builder`, `d_rocket_lints`, `d_rocket_engine_sqlite`, `d_rocket_engine_postgres`, `d_rocket_engine_web` (lockstep since 2.0.0) |
| Source | `github.com/torogoz-tech/d_rocket` |
| pub.dev | `pub.dev/packages/d_rocket` (and 5 siblings) |

The five legacy packages (`d_serializer`,
`d_serializer_builder`, `d_rest`, `d_rest_build`, `d_builder`)
are absorbed. They are no longer published; `d_rocket 2.0.0`
is the single source of truth for the data layer.

---

## Shipped versions

### 1.0.0 — The unified rename (June 2026)

The five legacy packages were absorbed into a single `d_rocket`
package. The `Rocket` prefix was dropped from every public
type and CLI command name (`RocketDb` → `Db`, `RocketTable` →
`@Table`, `d_rocket:rocket_migration` → `d_rocket:migration`,
etc.). The four legacy packages were marked deprecated and
lockstep versioning was introduced (every `d_rocket` release
pairs with a same-number `d_rocket_builder` release).

See [`RELEASE_1.0.0.md`](RELEASE_1.0.0.md) for the full
release notes.

### 1.1.0 — Reactive queries + bulk operations

`watch()` returns a `Stream` that re-emits on every
`saveChanges()`. `executeUpdateAsync` / `executeDeleteAsync`
for bulk operations that do not need entity hydration.

### 1.1.1 — Production-readiness

Three production-readiness fixes:

- **Sync queue persistence.** `SyncQueueStore` writes the
  pending sync ops to a `d_rocket_sync_queue` table in the
  same DB, inside the same transaction as the data write. A
  crash between `saveChanges()` and `sync()` no longer loses
  queued changes.
- **`PRAGMA foreign_keys = ON` on every `Db.open()`.** The
  `REFERENCES` clauses in the DDL are now enforced at
  runtime.
- **Codegen emits `CREATE INDEX` and `REFERENCES`.**

### 1.2.0 — Auto-migrations

Adds the auto-migration system. `Db.open(entityMetas: [...],
autoMigrate: true)` computes the diff between the
codegen-emitted schema and the last applied snapshot, applies
the safe changes (CREATE TABLE / CREATE INDEX / ADD COLUMN
nullable or with default) in a single transaction, and reports
the unsafe changes (DROP / MODIFY) via
`db.pendingSchemaDiff()`. A new `d_rocket_schema_state` table
tracks the last applied snapshot. The conservative default:
nothing is destroyed silently.

### 1.2.1 — Doc parity

Doc audit pass. The shared docs (`ROADMAP`, `BUG_REVIEW`,
`STATUS`) and the `d_rocket` README are rewritten to reflect
1.2.0 state. The B-09 bug (validation gap in `join_` /
`groupJoin_` arity) is fixed.

### 1.2.2 — Last 1.x release

Constraint bump for downstream consumers. The 1.x line is
now in maintenance mode (bug fixes and security patches only,
no new features).

### 2.0.0 — Engine-agnostic multi-engine (current)

The ORM is decoupled from the engine. Three engines ship as
separate packages (`d_rocket_engine_sqlite`,
`d_rocket_engine_postgres`, `d_rocket_engine_web`). The lints
move to a separate `d_rocket_lints` package. The realtime
annotations are renamed (`@WebSocketRoute` →
`@WebSocketClient`, `@SseRoute` → `@SseClient`). The
auto-migrator is rewritten on top of
`pendingSchemaDiff()` + `runAutoMigrations()`. The
`d_rocket_builder:rocket_migration` and
`d_rocket_builder:record` builders are new.

See [`RELEASE_2.0.0.md`](RELEASE_2.0.0.md) for the full
release notes and the breaking-change list.

---

## Post-2.0.0 candidates

Items that have been discussed for the 2.x line. Listed in
priority order; the maintainer picks a subset for each
monthly release. Anything not picked in a given month rolls
to the next monthly release.

### Tier 1 — engine parity (next 1-2 monthly releases)

- **Parity tests for Postgres + Web parity with the SQLite
  test suite.** The Postgres engine currently has 18
  dedicated tests; the Web engine has a smoke test. Closing
  this gap is the highest-priority post-2.0.0 work because
  it unblocks the engine as a first-class target.
- **Engine package scoring.** The same `DbSet<T>` LINQ
  chain should produce the same result on SQLite, Postgres,
  and Web for every test. The discrepancy matrix (engine ×
  test) is currently at SQLite: 100% / Postgres: 70% / Web:
  40%; the goal is 100% on all three.
- **A `connectivity_plus` integration for the
  `ConnectivityProvider`.** A dev_dependencies-only helper
  package that wires `package:connectivity_plus` to the
  `ConnectivityProvider` interface.

### Tier 2 — observability + tooling (next 2-3 monthly releases)

- **`DbInterceptor` audit log example.** A reference
  interceptor that logs every `onEntitySaving` event with
  the user id, timestamp, and field-level diff. Currently the
  `DbInterceptor` chain is shipped but not the reference
  interceptor.
- **A bench directory.** Cross-engine benchmarks
  (insert / update / delete / select-by-pk / select-by-where /
  join / aggregate) for SQLite, Postgres, and Web, with a
  markdown report generated on every release.
- **OpenAPI sync.** A `d_rocket:openapi` CLI that reads the
  `@RestClient` interfaces and generates an OpenAPI 3.1
  document (or the reverse: reads an OpenAPI doc and emits
  the `@RestClient` interfaces).

### Tier 3 — community asks (next 3-6 monthly releases)

- **Form binding (`@RocketForm`).** Declarative form model
  with validation. Would be Layer 7.
- **Benchmarks vs `drift`.** A "d_rocket vs drift"
  performance comparison across 10 common ORM operations.
- **Dart macros.** Eliminate `part '*.g.dart';` directives
  via the new `dart macros` package. Requires
  `analyzer ^13.0.0` (currently `^10.0.0`).
- **`d_rocket_admin`.** A batteries-included admin UI for
  browsing and editing a `DbContext` from a web browser. This
  is a separate package, not part of `d_rocket` itself.

### Out of scope (per project policy)

- **NoSQL support.** d_rocket is a SQL ORM. If you need a
  NoSQL store, look at `Isar` or `Hive` (both Flutter-first).
  d_rocket will not gain a document store, a graph store, or
  a key-value store.
- **Hand-written `MigrationBase` removed in favor of
  auto-migration.** Auto-migration handles the 80% case. The
  20% (drops, type changes, data migrations) is inherently
  app-specific and will never be safely auto-inferable. The
  hand-written system stays.
- **Auto-rename of columns without user confirmation.** The
  rename heuristic in 2.0.0 is a *suggestion*, not an
  auto-apply. The user has to confirm. This will not change.

---

## Release cadence

`d_rocket 2.1.0` will ship on the first Tuesday of next
month. Bug fixes can ship at any time as patch releases. See
[`RELEASE_CADENCE.md`](RELEASE_CADENCE.md) for the full
policy, the calendar of upcoming releases, and the criteria
for out-of-band patch releases.
