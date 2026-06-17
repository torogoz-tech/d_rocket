# 01 — Overview

## What is d_rocket?

`d_rocket` is a single-package framework for the **data layer** of
Dart and Flutter applications. It replaces the constellation of
JSON, HTTP, SQL, sync, and realtime libraries that an average
Dart/Flutter app accumulates, with **one package, one mental model,
one generator**.

The framework is organized as **six cooperating layers**, each
with its own annotation dialect, its own runtime, and its own
codegen phase. You can pick the layers you need and ignore the
rest:

| # | Layer | Purpose | Annotation |
|---|---|---|---|
| 1 | **Serialization** | JSON ↔ Dart | `@Serializable`, `@SerializableUnion` |
| 2 | **REST** | Typed HTTP clients | `@RestClient`, `@HttpGet` / `@HttpPost` / ... |
| 3 | **LINQ** | Query composition | `IQueryable<T>` (no annotation — queryable) |
| 4 | **ORM (SQLite)** | Local persistence | `@Table`, `@PrimaryKey`, `@Column`, `@ForeignKey`, `@Embedded`, `@Index` |
| 5 | **Sync (offline-first)** | Push/pull against a backend | `SyncProvider` (no annotation — class) |
| 6 | **Realtime** | WebSocket / SSE | `@WebSocketRoute`, `@SseRoute` |

A single `initializeD()` call wires every annotated class in your
project. There is no per-file `registerAll()`, no abstract
`AsyncQueryProvider` to wire up by hand, no `as` aliases.

## The six layers, in detail

### Layer 1 — Serialization

`@Serializable` turns a plain Dart class into a JSON-aware entity.
The codegen emits a `fromJson` constructor, a `toJson` method, and
registers the serializer with the central `Serializer` registry.
Wire format can be decoupled from Dart field names via
`@JsonKey` and `JsonNaming`. Sealed sum types are supported with
`@SerializableUnion` (discriminator dispatch).

**Lives in:** `lib/src/serializer/`.
**Docs:** [04-layer-1-serialization.md](04-layer-1-serialization.md).

### Layer 2 — REST

`@RestClient` is a typed interface; methods annotated with
`@HttpGet`, `@HttpPost`, `@HttpPut`, `@HttpPatch`, `@HttpDelete`,
or `@HttpHead` are implemented by the codegen with full
interceptor, retry, rate-limit, circuit-breaker, and response-cache
support. Parameter binding via `@Path`, `@Query`, `@Header`,
`@Body`, `@Field`, `@Part`, `@RawBody`. Streaming endpoints via
`Stream<T>` return types. Cancellable requests via
`CancelToken`.

**Lives in:** `lib/src/rest/`.
**Docs:** [05-layer-2-rest.md](05-layer-2-rest.md).

### Layer 3 — LINQ

`IQueryable<T>` with deferred execution. 40+ operators across
filter, project, page, order, set, quantifier, aggregate, element,
convert, join, and group. Async terminals suffixed with `*Async_`
return a `Future`. The expression tree is the same in three
contexts:

- In-memory: over `Iterable<T>` (LINQ-to-objects).
- Over a `DbSet<T>`: pushed down to SQL by the LINQ provider.
- Over a JSON list: parsed on the client side.

**Lives in:** `lib/src/linq/`.
**Docs:** [06-layer-3-linq.md](06-layer-3-linq.md).

### Layer 4 — ORM (SQLite)

`@Table` defines a row. `Db.open(path: 'app.db')`
opens the file. `DbSet<T>` is the typed table handle.
`saveChanges()` flushes inserts, updates, and deletes in a single
transaction. Eager-loading via `include_<T>()`. Reactive
queries via `watch()`. SQLite is bundled via `package:sqlite3`
— no provider indirection, no abstract pattern.

**Lives in:** `lib/src/orm/` and `lib/src/sqlite/`.
**Docs:** [07-layer-4-orm.md](07-layer-4-orm.md).

**Key 1.2.0 feature — auto-migrations.** When
`Db.open(entityMetas: [...], autoMigrate: true)`
is set, d_rocket computes the diff between the
codegen-emitted schema and the last applied
snapshot, applies the safe changes in a single
transaction, and reports the unsafe changes
(DROP, MODIFY) via `db.pendingSchemaDiff()`. The
conservative default: nothing is destroyed
silently.

### Layer 5 — Sync (offline-first)

`SyncProvider` is the interface your backend integration
implements. The runtime persists `SyncOp`s to the local
SQLite database, runs them through the push pipeline, and
listens to a pull pipeline for server-side changes.
Conflict resolution is pluggable (last-writer-wins,
server-wins, client-wins, or a custom callback).
Identity persistence survives process restarts.

**Lives in:** `lib/src/sync/`.
**Docs:** [08-layer-5-sync.md](08-layer-5-sync.md).

### Layer 6 — Realtime

`@WebSocketRoute` and `@SseRoute` annotate methods on an
abstract class; the codegen emits a `Stream<T>`-returning
client that handles reconnection with exponential backoff
and a heartbeat / ping. The same JSON serializer from
Layer 1 is reused for inbound and outbound payloads.

**Lives in:** `lib/src/realtime/`.
**Docs:** [09-layer-6-realtime.md](09-layer-6-realtime.md).

## The design philosophy

`d_rocket` is built on five design principles:

1. **One mental model.** A `@Serializable` is a `@Serializable`
   in memory, on the wire, in the database, and in a sync op.
   There is no separate "DTO" and "entity" concept. The same
   class can be all of those at once, and the codegen handles
   the conversion.

2. **One generator.** The codegen package `d_rocket_builder`
   reads the annotated sources and emits:
   - per-class `fromJson` / `toJson` and a central
     `register<X>Serializer` call;
   - per-interface `RestClient` implementations with
     interceptors, retry, and serialization wired in;
   - per-entity `EntityMeta` (table name, columns,
  indexes, primary-key, embedded fields) for the
  ORM. The auto-migrator (1.2.0) reads the
  `EntityMeta` list at runtime to compute schema
  diffs;
   - a single `d_rocket_registry.g.dart` with the central
     `initializeD()` that registers every annotated class
     in the project.

3. **Async-first.** Every terminal query operator has an
   `*Async_` sibling that returns a `Future`. There is no
   `then` chain, no callback hell. `await db.set<T>().toListAsync_()`
   is the natural shape.

4. **SQLite-bundled.** `Db.open(path: 'app.db')` works
   out of the box. `package:sqlite3` is the only engine
   shipped. If you want a different engine, the
   `AsyncQueryProvider` contract is open for you to implement
   your own provider — but in the vast majority of cases you
   just want SQLite, and it's right there.

5. **Offline-first.** The local database is the source of
   truth for reads. Writes queue into a `SyncOp` log; the
   sync runtime flushes them in the background. Reads
   never block on the network. If the network is up and
   you want realtime updates, attach a `WebSocketClient`
   and inject the events into a `DbSet<T>.watch()`.

## What d_rocket is **not**

- **Not an ORM for any database but SQLite.** Other engines
  can be plugged in via `AsyncQueryProvider`, but the bundled
  engine is SQLite. If you need Postgres or MySQL, the
  `d_rocket_provider_*` family is where to look.

- **Not a web framework.** No router, no controller, no
  template engine. `d_rocket` is the data layer; the
  presentation layer is your choice (Flutter, shelf, etc.).

- **Not a no-code solution.** Annotations generate code, but
  the framework is opinionated about the *shape* of your
  data. The contract between the framework and your code is
  explicit and documented.

- **Not a re-implementation of `package:http`.** `d_rocket`
  uses `package:http` under the hood. It does not replace
  it; it adds typed interfaces, interceptors, retry, and
  resilience on top.

- **Not a migration of `d_serializer` or `d_rest`.** Those
  were absorbed into `d_rocket` at version 1.0.0. The
  migration path is documented in
  [CHANGELOG.md](../CHANGELOG.md).

## The runtime + codegen relationship

`d_rocket` (the runtime package) and `d_rocket_builder` (the
codegen package) are two halves of the same framework. The
runtime ships the API surface (`@Serializable`, `@RestClient`,
`@Table`, etc.) and the implementation
(`Db`, `DbSet<T>`, `IQueryable<T>`, etc.). The codegen
ships the `build_runner` integration that reads your
annotations and emits the wiring.

A typical project depends on both:

```yaml
dependencies:
  d_rocket: ^1.0.0   # runtime

dev_dependencies:
  d_rocket_builder: ^1.0.0   # codegen
  build_runner: ^2.4.13
```

The codegen is a **dev dependency** because it never ships
with the app. The generated `*.g.dart` files are committed
to your project (or generated on CI) and the runtime
consumes them at startup.

## The directory layout

```
lib/
  d_rocket.dart                ← public barrel; imports everything
  src/
    serializer/                ← Layer 1
      serializable.dart
      serializable_union.dart
      json_naming.dart
      json_key.dart
      format.dart
      serializer.dart           ← central registry
      unknown_key_policy.dart
    rest/                      ← Layer 2
      rest_client.dart
      rest_config.dart
      http_get.dart             ← verbs
      ...
      interceptors/            ← the chain
      clients/                 ← wrap-around clients (retry, rate limit, ...)
    linq/                      ← Layer 3
      queryable.dart
      operators/                ← every operator
      expr.dart                 ← the AST
    sqlite/                    ← Layer 4 (engine)
      query_provider.dart
      queryable.dart
      sql_translator.dart       ← LINQ → SQL
    orm/                       ← Layer 4 (context, migrations)
      db.dart
      db_context.dart
      db_set.dart
      navigation_populator.dart
      change_tracker.dart
    sync/                      ← Layer 5
      sync_provider.dart
      sync_op.dart
      conflict_resolver.dart
    realtime/                  ← Layer 6
      websocket_client.dart
      sse_client.dart
  example/
    bookstore.dart              ← complete runnable example
bin/
  migration.dart         ← `d_rocket:migration` CLI
  closure.dart           ← `d_rocket:closure` CLI
test/
  ...
docs/
  ...                          ← this folder
```

## When to use which layer

You don't have to use all six. The framework is designed to
be picked apart.

| You need... | Use these layers |
|---|---|
| JSON for REST APIs | 1 |
| A typed HTTP client | 1 + 2 |
| Local data persistence | 1 + 4 |
| A full offline-first app | 1 + 3 + 4 + 5 |
| Live UI updates from a server | 1 + 4 + 6 |
| Local-first reactive UI | 1 + 4 (with `watch()`) |
| A complete data layer | 1 + 2 + 3 + 4 + 5 + 6 |

Most apps fall into the "complete data layer" row. The
layers that almost everyone uses are 1, 3, and 4. Layer 2
is needed if you have a remote API. Layers 5 and 6 are
needed if you have multi-device sync or live updates.

## Next steps

- New to the framework? → [02 — Quickstart](02-quickstart.md)
- Setting up a project? → [03 — Installation](03-installation.md)
- Migrating from `d_serializer` / `d_rest` / sqflite? → [13 — FAQ](13-faq.md)
- Want the design details? → [14 — Architecture](14-architecture.md)
