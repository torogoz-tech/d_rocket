# d_rocket — Extended documentation

This folder is the **complete reference** for the `d_rocket` framework.
The top-level [README](../README.md) on pub.dev is the landing page;
this folder is everything you need to actually use the framework
day-to-day.

> **Note**: this folder is **not** included in the published package.
> It lives in the source repository on GitHub. The published
> package ships only the runtime, the codegen, the README, the
> CHANGELOG, and the LICENSE. This is the standard Dart pub layout.

---

## Table of contents

### Getting started

- **[01 — Overview](01-overview.md)** — what `d_rocket` is, why
  it exists, the six layers, and the design philosophy.
- **[02 — Quickstart](02-quickstart.md)** — a complete runnable
  example from `pubspec.yaml` to a working `Db` query, in
  five minutes.
- **[03 — Installation](03-installation.md)** — pubspec config,
  `build_runner` setup, dependency choices, and troubleshooting.

### The six layers

The framework is organized as **six cooperating layers**. Each
layer has its own annotation dialect, its own runtime, and its own
codegen phase. You can pick the layers you need and ignore the
rest.

- **[Layer 1 — Serialization](04-layer-1-serialization.md)** —
  `@Serializable` classes, `JsonNaming`, `JsonKey`, sealed unions
  with `@SerializableUnion`, custom `Format`s, and the
  `Serializer` registry.
- **[Layer 2 — REST](05-layer-2-rest.md)** — `@RestClient`
  interfaces, `@HttpGet` / `@HttpPost` / etc., parameter binding,
  resilience (`RetryPolicy`, `CircuitBreaker`, `RateLimit`),
  and the `RestInterceptor` chain.
- **[Layer 3 — LINQ](06-layer-3-linq.md)** — `IQueryable<T>`,
  every operator, async terminals, expression trees, and SQL
  push-down via the `Expr` DSL.
- **[Layer 4 — ORM (SQLite)](07-layer-4-orm.md)** —
  `@Table` entities, change-tracked `DbSet<T>`, includes,
  reactive `watch()`, bulk operations, and the `Db`
  facade.
- **[Layer 5 — Sync (offline-first)](08-layer-5-sync.md)** —
  `SyncProvider` interface, `SyncOp` queue, push / pull
  pipelines, conflict resolution policies, and identity
  persistence.
- **[Layer 6 — Realtime](09-layer-6-realtime.md)** —
  `@WebSocketRoute` and `@SseRoute`, typed `Stream<T>`
  methods, reconnection with backoff, and heartbeat.

### Migrations and tooling

- **[Migrations](10-migrations.md)** — `Migration` base class,
  `MigrationStrategy` (declarative + imperative), the runner's
  upgrade / downgrade logic, and the migration history table.
- **[CLI tools](11-cli.md)** — `d_rocket:migration add`
  scaffolder, `d_rocket:migration doctor` validator, and
  `d_rocket:closure` Expr translator.

### Reference

- **[Cookbook](12-cookbook.md)** — real-world recipes:
  authentication, pagination, multi-tenant schemas, full-text
  search, audit logs, time-zone handling, schema versioning.
- **[FAQ](13-faq.md)** — common questions, gotchas, and
  performance notes.
- **[Architecture](14-architecture.md)** — internal design of
  each layer, the codegen pipeline, and how the layers
  communicate at runtime.

---

## Reading order

**If you're new to `d_rocket`:** start with the README, then
[01 — Overview](01-overview.md), then [02 — Quickstart](02-quickstart.md).

**If you've already done the quickstart and want depth:** read
[03 — Installation](03-installation.md), then the layer docs in
order 1 → 6 as you need them.

**If you're migrating from another framework (Entity Framework
Core, .NET LINQ, Retrofit, sqflite, etc.):** jump straight to the
layer that maps to your background:

| Your background | Start here |
|---|---|
| Entity Framework Core | [04 — Serialization](04-layer-1-serialization.md) + [07 — ORM](07-layer-4-orm.md) + [10 — Migrations](10-migrations.md) |
| .NET LINQ | [06 — LINQ](06-layer-3-linq.md) |
| Retrofit (Android) | [05 — REST](05-layer-2-rest.md) |
| sqflite / moor | [07 — ORM](07-layer-4-orm.md) + [10 — Migrations](10-migrations.md) |
| json_serializable / freezed | [04 — Serialization](04-layer-1-serialization.md) |

---

## How to read the code samples

Code samples in this documentation follow a few conventions:

- **Imports**: assume `import 'package:d_rocket/d_rocket.dart';` at
  the top of every file. Add `import 'package:my_app/d_rocket_registry.g.dart';`
  wherever a generated `initializeD()` is referenced.
- **Method names** on `Queryable<T>` use a trailing underscore to
  disambiguate from `Iterable<T>`'s built-in operators. So
  `where_`, `orderBy_`, `take_`, `toList_`. The first operator
  call on a `DbSet<T>` is clean (no underscore) because the
  bridge extension runs on the set, not on the queryable.
  See [06 — LINQ](06-layer-3-linq.md#the-underscore-convention)
  for the full convention.
- **Async terminals** are suffixed with `*Async_`. `toListAsync_`,
  `firstOrDefaultAsync_`, `countAsync_`. They return a `Future`.
- **Generated code** is shown as `// generated` comments at the
  top of the file. You don't write this code — the codegen does.

---

## Versioning and stability

This documentation is for `d_rocket` 1.0.0 and later. Within the
`1.x` series:

- **Patch versions** (1.0.x) — bug fixes only. Source-compatible.
- **Minor versions** (1.x) — additive features, new annotations,
  new operators. Source-compatible.
- **Major versions** (2.x) — breaking changes. The migration
  guide will be in [13 — FAQ](13-faq.md#how-do-i-migrate-between-major-versions).

See [CHANGELOG.md](../CHANGELOG.md) for the per-release detail.

---

## Contributing to this documentation

Found a typo, a broken example, or a missing recipe? Open an
issue on the [GitHub repository](https://github.com/torogoz-tech/d_rocket/issues)
with the `docs` label. The framework itself is stable; the
documentation is always welcome to grow.
