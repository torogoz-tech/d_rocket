# d_rocket — Status

> One-page snapshot of where the framework is today. If you are
> evaluating d_rocket, this is the page to read.

## Where we are

| Metric | Value |
|---|---|
| Latest release | **1.2.0** (auto-migrations) |
| Previous release | 1.1.1 (sync queue persistence + FK enforcement) |
| Test suite | 857 pass + 1 skip (libsqlcipher) |
| Analyzer warnings | 0 |
| pana score | 140/160 (gap: Web not supported, `analyzer` capped at `^8.0.0` by `custom_lint_builder 0.8.1`) |
| Public packages | `d_rocket`, `d_rocket_builder` (lockstep since 1.1.1) |
| Lockstep versioning | yes — every `d_rocket` release pairs with a same-number `d_rocket_builder` release |
| Source | `github.com/torogoz-tech/d_rocket` |
| pub.dev | `pub.dev/packages/d_rocket`, `pub.dev/packages/d_rocket_builder` |

## What d_rocket is (one-liner per layer)

1. **Serialization** — `@Serializable` with `fromJson` / `toJson`, `JsonNaming`, sealed unions, per-property formatters, three unknown-key modes.
2. **REST** — `@RestClient` with retry, rate limit, circuit breaker, response cache, interceptor chain.
3. **LINQ** — deferred `IQueryable<T>` with 30+ operators, push-down to SQL on `DbSet<T>`.
4. **ORM (SQLite)** — `DbContext` + `DbSet<T>` + change tracking + code-first `MigrationBase` + auto-migrations + `include_<T>()` + reactive `watch()`.
5. **Sync** — `SyncProvider` + persistent `SyncOp` queue + push / pull + pluggable conflict resolution.
6. **Realtime** — `@WebSocketRoute` + `@SseRoute` + typed `Stream<T>` + exponential backoff + heartbeat.

## Releases at a glance

### 1.2.0 — auto-migrations (current)

- `Db.open(entityMetas: [...], autoMigrate: true)` computes the diff between the codegen-emitted schema and the last applied snapshot, applies the safe changes (CREATE TABLE / CREATE INDEX / ADD COLUMN nullable or with default) in a single transaction, and reports the unsafe changes (DROP / MODIFY) via `db.pendingSchemaDiff()`.
- New public API: `Db.runAutoMigrations()`, `Db.pendingSchemaDiff()`.
- New `d_rocket_schema_state` table (single-row key-value) tracks the last applied snapshot.
- Conservative default: nothing is destroyed silently.

### 1.1.1 — production-readiness (previous)

- Sync queue persisted to `d_rocket_sync_queue` in the same DB, atomic with the data write.
- `PRAGMA foreign_keys = ON` on every `Db.open()` (FKs are now enforced, not just parsed).
- Codegen emits `CREATE INDEX` for `@Index` annotations and `REFERENCES` for `@Column(isForeignKey: true)`.

### 1.1.0 (and earlier)

- The 1.0 rename (drop `Rocket` prefix from every public type and CLI command name).
- The four legacy packages (`d_serializer`, `d_rest`, `d_serializer_builder`, `d_rest_build`) marked deprecated and the migration path documented.

## Roadmap (1.3.0 candidates)

| Feature | Effort | Why it matters |
|---|---|---|
| REST "esteroides" (rate limit, circuit breaker, response cache) | 1-2 sprints | The 1.0 doc promised these; rate limit and circuit breaker are partially shipped; the cache is missing. |
| PostgreSQL integration tests via testcontainers | 1 sprint | The Postgres provider is shipped but untested against a live server. |
| Missing LINQ operators (selectMany_, toLookup_, reverse_, defaultIfEmpty_, zip_, sequenceEqual_) | 1 sprint | Closes the last gap in the LINQ surface. |
| CLI scaffolder for migrations (EF Core parity) | 1 sprint | The `bin/migration.dart` exists but is minimal; the dev has to write `MigrationBase` subclasses by hand. |
| Mark the 4 legacy packages as `discontinued` on pub.dev | 1 day | The packages are already marked `DEPRECATED` locally; pub.dev needs the same. |
| Codegen split (`d_rocket_lints` out of `d_rocket_builder`) | 1 sprint | Bumps `analyzer` from `^8.0.0` to `^13.0.0` (5 majors behind). |

## Where to read more

- [README](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/README.md) — landing page, what d_rocket is, why it exists, how it compares.
- [CHANGELOG](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/CHANGELOG.md) — every release.
- [ROADMAP](https://github.com/torogoz-tech/d_rocket/blob/main/doc/ROADMAP_d_rocket.md) — historical phases (0–5.6) + the 1.3.0 candidates.
- [BUG_REVIEW](https://github.com/torogoz-tech/d_rocket/blob/main/doc/BUG_REVIEW_d_rocket.md) — bugs found and fixed (1 through B-09, all closed as of 1.2.1).
- [FAQ](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/13-faq.md) — common questions and the auto-migrations guide.
- [doc/](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/) — the full reference (overview, quickstart, installation, 6 layer guides, migrations, CLI, cookbook, FAQ, architecture).
