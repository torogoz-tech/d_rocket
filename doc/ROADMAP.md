# d_rocket — Roadmap

> Historical phases (0.0.1-dev through 1.2.0) and the 1.3.0
> candidates. Updated 2026-06-15.
>
> This doc supersedes the original `ROADMAP_d_rocket.md` from
> 0.0.1-dev, which was frozen at "0.3.0-dev, 198 tests" and is no
> longer representative of where the framework is.

---

## Where we are (2026-06-15)

| | |
|---|---|
| Version | **1.2.0** (auto-migrations) |
| Tests | 857 pass + 1 skip |
| Analyzer | 0 warnings |
| pana | 140/160 (Web not supported, analyzer pinned to ^8.0.0) |
| Packages on pub.dev | `d_rocket`, `d_rocket_builder` (lockstep since 1.1.1) |
| Source | github.com/torogoz-tech/d_rocket |

The two legacy ecosystems (`d_serializer`, `d_rest`, `d_serializer_builder`,
`d_rest_build`) are absorbed. They are not published; d_rocket 1.0+ is
the single source of truth for the data layer.

---

## Shipped phases (historical)

### Phase 0 — Bootstrap (0.0.1-dev, Feb 2026)

Monorepo layout, `d_rocket` package with empty public barrel,
`d_rocket_builder` placeholder. Two-arg constructor on every
class, 2 tests, 0 issues. **Done.**

### Phase 1 — Serialization + REST (0.1.0, Mar 2026)

`@Serializable` with `fromJson` / `toJson`, `JsonNaming` policy,
sealed unions, three unknown-key modes. `@RestClient` with
`@HttpGet` / `@HttpPost` / `@Body` / `@Query` / `@Header`.
Serializer + rest_client codegen outputs `.g.dart`. **Done.**

### Phase 1.5 — `initializeD()` (0.1.5, Mar 2026)

Replaced the per-class `register<MyType>Record()` calls with a
single `initializeD()` call that wires every `@Serializable`,
`@RestClient`, and `@Table` in the project. The
`d_rocket_builder:rocket_registry` builder emits the
`d_rocket_registry.g.dart` file. **Done.**

### Phase 2 — LINQ (0.2.0, Mar 2026)

`IQueryable<T>` with deferred execution, expression trees, 30+
operators across filter, project, group, page, order, set,
quantifier, aggregate, element, convert, join. In-memory
provider for unit tests; SQL push-down deferred. **Done.**

### Phase 3 — ORM (SQLite) (0.3.0-dev, Apr 2026)

`DbContext` + `DbSet<T>` + change tracking. `MigrationBase`
subclass + `MigrationRunner` for code-first migrations. Reactive
`watch()`. The SQL push-down for LINQ became the
`TranslatableProvider`. **Done** (shipped as part of 1.0).

### Phase 4 — Migrations (1.0.0, May 2026)

`MigrationStrategy` with version-driven dispatch (declarative or
imperative). `MigrationTransactionFactory` for atomic
transactions. `initializeD()` integrates with the migrations
table. **Done.**

### Phase 5 — Realtime + Sync (1.0.0, May 2026)

`@WebSocketRoute` / `@SseRoute` for typed `Stream<T>` with
reconnection. `SyncProvider` interface, `SyncOp` queue,
`ConflictPolicy` for last-write-wins / versioned. The realtime
codegen produces a typed client. **Done.**

### 1.0.0 — The rename (Jun 2026)

Dropped the `Rocket` prefix from every public type and CLI
command name (`RocketDb` → `Db`, `RocketTable` → `@Table`,
`d_rocket:rocket_migration` → `d_rocket:migration`, etc.).
Marked the four legacy packages as deprecated. Lockstep
versioning convention introduced (every d_rocket release pairs
with a same-number d_rocket_builder release). **Done.**

### 1.1.0 — Reactive queries + bulk operations (Jun 2026)

`watch()` returns a `Stream` that re-emits on every
`saveChanges()`. `executeUpdateAsync` / `executeDeleteAsync`
for bulk operations that don't need entity hydration. **Done.**

### 1.1.1 — Production-readiness (Jun 2026)

Three production-readiness fixes paired with the codegen
side. See the [CHANGELOG](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/CHANGELOG.md#111--2026-06-15)
for the full list:

- **Sync queue persistence.** `SyncQueueStore` writes the
  pending sync ops to a `d_rocket_sync_queue` table in the same
  DB, inside the same transaction as the data write. A crash
  between `saveChanges()` and `sync()` no longer loses queued
  changes.
- **`PRAGMA foreign_keys = ON` on every `Db.open()`.** The
  `REFERENCES` clauses in the DDL are now enforced at runtime.
- **Codegen emits `CREATE INDEX` and `REFERENCES`.** The
  builder's `MigrationGenerator` now calls
  `_EntityMeta.createIndexStatements()` in the `up()` template,
  and `@Column(isForeignKey: true)` derives the target table
  from the field name and emits the clause.

**Done.**

### 1.2.0 — Auto-migrations (Jun 2026)

Adds the auto-migration system. `Db.open(entityMetas: [...],
autoMigrate: true)` computes the diff between the codegen-emitted
schema and the last applied snapshot, applies the safe changes
(CREATE TABLE / CREATE INDEX / ADD COLUMN nullable or with
default) in a single transaction, and reports the unsafe changes
(DROP / MODIFY) via `db.pendingSchemaDiff()`. The conservative
default: nothing is destroyed silently.

A new `d_rocket_schema_state` table (single-row key-value)
tracks the last applied snapshot. The two migration systems
(hand-written `MigrationBase` and auto-migration) coexist;
hand-written runs first, auto-migration runs after.

**Done.**

### 1.2.1 — Doc parity (Jun 2026)

A doc audit pass. The shared docs (this file, `BUG_REVIEW`,
`STATUS`) and the d_rocket README are rewritten to reflect
1.2.0 state. The B-09 bug (validation gap in `join_` /
`groupJoin_` arity) is fixed in 1.2.1. **Done.**

---

## 1.3.0 candidates

The audit pass surfaced six candidates for the next minor
release. Listed in priority order:

### 1. REST "esteroides" (1-2 sprints)

The 1.0 doc promised: retry, rate limit, circuit breaker,
response cache, OpenAPI sync.

- ✅ Retry — done in 0.3.0-dev (`retrying_http_client.dart`).
- ❌ Rate limit — `rate_limited_http_client.dart` is a stub.
- ❌ Circuit breaker — `circuit_breaker_http_client.dart` is
  a stub.
- ❌ Response cache — not implemented.
- ❌ OpenAPI sync — not implemented.

**Why it matters:** the marketing claims "REST with steroids"
are partly empty. Anyone auditing the package will see the gap.
The rate limit + circuit breaker are the minimum needed to
keep the claim honest. The response cache and OpenAPI sync are
1.3.0+.

### 2. PostgreSQL integration tests (1 sprint)

The Postgres provider (`lib/src/orm/d_rocket_provider_postgres`)
is shipped but untested against a live server. Today the
provider is `publish_to: none` because of this gap. A test suite
with `testcontainers` (or a long-lived dev Postgres) would
unblock the publish.

**Why it matters:** "1.1.1 ships Postgres support" is currently
"the code exists; nobody has run it." A 1.3.0 test pass would
flip the claim to "the code exists and works against a live
server."

### 3. Missing LINQ operators (1 sprint)

The `IQueryable<T>` surface has 30+ operators; six are missing
or incomplete:

- `selectMany_` — flatMap (collections of collections → flat
  collection).
- `toLookup_` — group by key into a `Map<K, List<V>>`.
- `reverse_` — reverse the order.
- `defaultIfEmpty_` — replace empty source with a default.
- `zip_` — pairwise merge with another `IQueryable`.
- `sequenceEqual_` — deep equality with another `IQueryable`.

`selectMany_` is the highest-value (used by `IncludeMany`, by
auto-migration diff serialization, and by users). The other
five are 1-2 day each.

### 4. CLI scaffolder for migrations (1 sprint)

The `bin/migration.dart` exists but is minimal. The goal is
EF Core parity:

```bash
$ dart run d_rocket:migration add "Add note to patients"
→ 1 safe diff detected (ADD COLUMN note TEXT)
→ Generating lib/migrations/004_add_note_to_patients.dart
→ Up: ALTER TABLE patients ADD COLUMN note TEXT
→ Review the file, then run `migrations apply`

$ dart run d_rocket:migration check
→ 1 unsafe diff pending (DROP COLUMN note in patients)
→ Block deploy (exit 1)
```

The codegen would emit a `MigrationBase` subclass with the
`up()` body pre-populated. The `check` command wraps
`db.pendingSchemaDiff()` and exits non-zero on unsafe.

### 5. Mark the 4 legacy packages as `discontinued` (1 day)

The packages are already `DEPRECATED.md` locally; pub.dev
needs the same. One PR per package, no code changes.

### 6. Codegen split (`d_rocket_lints` out of `d_rocket_builder`) (1 sprint)

`d_rocket_builder` depends on `custom_lint_builder ^0.8.1`,
which caps `analyzer` at `^8.0.0`. The current `analyzer` is
`^13.0.0` — we are 5 majors behind. Moving the lints
(`linq_closure_lint`, `n_plus_one_lint`) into a separate
`d_rocket_lints` package would unblock the bump.

This is a structural change that touches every consumer of
`d_rocket_builder`. The migration is mechanical but needs a
deprecation cycle.

---

## Beyond 1.3.0

Items that are not on the immediate roadmap but have been
discussed:

- **Form binding (`@RocketForm`)** — declarative form model
  with validation. Would be Layer 7.
- **PostgreSQL first-class support** — currently the Postgres
  provider is shipped but not the testbed of choice. A future
  release could promote it to the default (overriding SQLite)
  for server-side Dart.
- **Dart macros** — eliminate `part '*.g.dart';` directives
  via the new `dart macros` package. Would require
  `analyzer ^13.0.0` (the same blocker as the lints split).
- **Benchmarks vs `drift`** — a "d_rocket vs drift"
  performance comparison across 10 common ORM operations
  (insert, update, delete, select-by-pk, select-by-where,
  join, aggregate, etc.). Would be a blog post + a `bench/`
  directory in the repo.
- **`d_rocket_admin`** — a batteries-included admin UI for
  browsing and editing a `DbContext` from a web browser. This
  is a separate package, not part of `d_rocket` itself.

---

## Out of scope (forever)

- **Web target for the ORM.** The `sqlite3` dependency is a
  thin Dart wrapper over `dart:ffi`, which the Dart-to-JS
  compiler does not support. There is no `dart:ffi` on the Web
  target. The other five layers (1, 2, 3, 5, 6) are
  platform-neutral and work on the Web; the storage layer
  (Layer 4) does not.
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
  rename heuristic in 1.2.0 is a *suggestion*, not an
  auto-apply. The user has to confirm. This will not change.
