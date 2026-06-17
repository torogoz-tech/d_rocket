# d_rocket

> **Dart's data rocket — serialize, query, persist, sync.**

`d_rocket` is a single-package framework for the data layer of Dart and
Flutter applications. It unifies the six concerns that, in most stacks,
force you to glue together half a dozen different libraries:

| Layer | What you get |
|---|---|
| **1 — Serialization** | `@Serializable` classes with type-safe `fromJson` / `toJson`, union types, custom formatters, and policies for unknown keys. |
| **2 — REST** | `@RestClient` interfaces with retry, backoff, rate limiting, circuit breaker, response cache, and a full interceptor chain. |
| **3 — LINQ** | Deferred-execution `IQueryable<T>` with 30+ operators: filter, project, group, join, aggregate, set, quantifier, element, page. |
| **4 — ORM (SQLite)** | `DbContext`, change-tracked `DbSet<T>`, code-first + auto-migrations, `saveChanges()`, eager-loading `include_<T>()`, reactive `watch()`. |
| **5 — Sync (offline-first)** | `SyncProvider` interface, persistent `SyncOp` queue (survives crashes), push / pull pipelines, conflict-resolution policies. |
| **6 — Realtime** | `@WebSocketRoute` and `@SseRoute`, typed `Stream<T>`, reconnection with exponential backoff, heartbeat. |

All six layers share a build-time **codegen** package
([`d_rocket_builder`](https://pub.dev/packages/d_rocket_builder)) that
wires the whole thing up with a single `initializeD()` call.

```dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';

void main() async {
  initializeD();
  final db = await Db.open(
    path: 'app.db',
    entityMetas: <EntityMeta>[Todo.entityMeta],
    autoMigrate: true,
  );
  db.set<Todo>().add(Todo(id: 1, title: 'Ship d_rocket 1.2'));
  await db.saveChanges();
  final pending = await db.set<Todo>()
      .where_(t => t.done == false)
      .toListAsync_();
  print('${pending.length} pending todos');
}
```

---

## What d_rocket is (and isn't)

**It is:** one framework, one mental model, one generator, for the
data layer of a Dart/Flutter app. Six layers that share types
(an entity is a `@Serializable` and a `@Table` at the same time;
a REST response is decoded by the same serializer that encodes a
sync envelope; a LINQ query against a `DbSet` becomes the same SQL
as a hand-written one). The codegen wires the parts; you write the
model.

**It isn't:** a Web framework (no `dart:ffi` on JS), an ORM with
"smart" relationships (the relationships are explicit annotations),
a code-first migration system that hides drops (it reports them,
never silently destroys data), or a batteries-included admin UI
(`d_rocket_admin` is being prototyped separately).

---

## Why d_rocket?

Most Dart/Flutter apps assemble their data layer from a constellation
of packages: one for JSON, another for HTTP, a third for SQLite, a
fourth for migrations, a fifth for offline sync, and a half-dozen
glue files that wire it all up. Each one has its own annotation
style, its own error model, its own dialect.

`d_rocket` replaces that with **one package, one mental model, one
generator**:

- **Annotation-driven.** Mark a class with `@Serializable`, an interface
  with `@RestClient`, an entity with `@Table`. The generator produces
  the wiring; you write the model.
- **One `initializeD()` call.** No per-file `registerAll()`, no `as`
  aliases, no manual injection of `fromJson` factories.
- **Async-first.** Every terminal query operator has an `*Async_`
  sibling that returns a `Future`. No `then` chains, no callback hell.
- **SQLite-bundled.** Open a database, get a typed set, query it.
  `package:sqlite3` is the only engine shipped out of the box; no
  provider indirection.
- **Encrypted at rest.** Pass `password: '…'` to `Db.open` and the
  database is opened as a SQLCipher database. Full-page AES,
  PBKDF2-HMAC-SHA512 key derivation, transparent to the rest of the
  stack.
- **Auto-migrations (1.2.0+).** Pass `entityMetas:` and
  `autoMigrate: true` to `Db.open`; d_rocket detects the diff between
  the codegen-emitted schema and the last applied snapshot, applies
  the safe changes (CREATE TABLE / CREATE INDEX / ADD COLUMN
  nullable or with default) in a single transaction, and reports
  the unsafe changes (DROP / MODIFY) for the user to handle
  explicitly. The conservative default: nothing is destroyed
  silently.
- **Persistent sync queue (1.1.1+).** The pending sync operations
  are persisted to a `d_rocket_sync_queue` table in the same
  database as the user data, inside the same transaction as the
  data write. A crash between `saveChanges()` and `sync()` no longer
  loses queued changes.
- **FK enforcement on by default (1.1.1+).** `PRAGMA foreign_keys
  = ON` is emitted on every `Db.open()`. The `REFERENCES` clauses
  in the DDL are enforced at runtime, not just parsed.
- **Production-tested.** 857 unit and integration tests cover all
  six layers and the codegen pipeline. 0 analyzer warnings.
  `pana 140/160`.

## How it compares (1-liner each)

| vs | Why d_rocket wins (or ties) |
|---|---|
| **freezed** (JSON) | Same `@Serializable` ergonomics + wires the same class into 5 other layers. |
| **json_serializable** (JSON) | Same codegen, plus REST + LINQ + ORM + sync + realtime on the same class. |
| **retrofit** (REST) | Same `@RestClient`, plus built-in retry, rate limit, circuit breaker, cache, interceptors. |
| **drift** (ORM) | Same SQL, but with a sync queue, a reactive `watch()`, and change tracking — no more `INSERT INTO ... RETURNING` + `notifyListeners()` boilerplate. |
| **sqflite** (SQLite) | Same engine, but with LINQ, migrations, change tracking, and sync out of the box. |
| **floor** (ORM) | Same compile-time codegen, but with REST + sync + realtime on the same class. |
| **Isar / Hive** (NoSQL) | d_rocket is SQL. You give up indexing tradeoffs, you get joins, transactions, ACID, and `SELECT` against any column. |

---

## Installation

Add the runtime and the codegen to your `pubspec.yaml`:

```yaml
dependencies:
  d_rocket: ^1.2.0

dev_dependencies:
  d_rocket_builder: ^1.2.0
  build_runner: ^2.4.13
```

Then fetch and run the generator once:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

You're ready. Import `package:d_rocket/d_rocket.dart` and call
`initializeD()` in `main()`.

## Quickstart

A complete runnable app in 30 lines — model, store, query:

```dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';

@Table()
class Todo {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final String title;
  @Column() final bool done;
  Todo({this.id = 0, required this.title, this.done = false});
}

void main() async {
  // 1. Wire every @Serializable / @RestClient / @Table
  //    in the project with one call.
  initializeD();

  // 2. Open a local SQLite database with auto-migrations.
  //    Safe changes (add column, add index, add table)
  //    are applied in a transaction; unsafe changes
  //    (drop, type change) are reported via
  //    db.pendingSchemaDiff().
  final db = await Db.open(
    path: 'app.db',
    entityMetas: <EntityMeta>[Todo.entityMeta],
    autoMigrate: true,
  );

  // 3. Insert.
  db.set<Todo>().add(Todo(title: 'Ship 1.2'));
  db.set<Todo>().add(Todo(title: 'Write docs'));
  await db.saveChanges();

  // 4. Query with LINQ.
  final pending = await db.set<Todo>()
      .where_(t => t.done == false)
      .orderBy_(t => t.title)
      .toListAsync_();
  print('${pending.length} pending todos');
}
```

For mixed hand-written and auto migrations, see the
[Migrations guide](https://github.com/torogoz-tech/d_rocket/blob/main/doc/10-migrations.md).

---

## The six layers at a glance

### Layer 1 — Serialization

```dart
@Serializable()
class Customer {
  Customer({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;
}

final json = customer.toJson();
final back = Customer.fromJson(json);
```

**Naming policy** — wire format doesn't have to match your Dart field
names (`@Serializable(jsonNaming: JsonNaming.snakeCase)`).
**Unknown keys** — three modes: `ignore`, `strict`, `capture`.
**Sealed unions** — `@SerializableUnion()` for sum types.

### Layer 2 — REST

```dart
@RestClient(baseUrl: 'https://api.example.com/v1')
abstract class ShopClient {
  @HttpGet('/products')
  Future<List<Product>> listProducts(@Query('category') String? category);

  @HttpPost('/orders')
  Future<Order> createOrder(@Body() OrderDraft draft);
}
```

**Resilience** — retry, rate limit, circuit breaker, response cache.
**Interceptors** — auth tokens, logging, tracing, metrics.

### Layer 3 — LINQ

```dart
final top = await products
    .asQueryable()
    .where_(p => p.category == 'electronics')
    .where_(p => p.price > 50)
    .orderByDescending_(p => p.price)
    .take_(10)
    .toListAsync_();
```

30+ operators across filter, project, page, order, set, quantifier,
aggregate, element, convert, join, and group.

**Push-down to SQL** — when the source is a `DbSet<T>`, the same
operators become SQL:

```dart
final avg = await db.set<Product>()
    .where_(p => p.category == 'electronics')
    .average_(p => p.price);
// => SELECT AVG(price) FROM products WHERE category = 'electronics'
```

### Layer 4 — ORM (SQLite)

```dart
@Table('orders')
class Order {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final int customerId;
  @Column() final double total;
  @Column() final String status;
  @Column(name: 'placed_at') final DateTime placedAt;
  @BelongsTo('customer', Customer) Customer? customer;
  @HasMany('order', LineItem) List<LineItem> items = [];
}

db.set<Order>().add(order);
await db.saveChanges();
```

**Includes** — `include_<Customer>().include_<LineItem>()`.
**Reactive** — `db.set<Product>().watch()` returns a `Stream` that
re-emits on changes.
**Migrations** — code-first (`MigrationBase`) and/or auto-migrations
(`Db.open(entityMetas: ..., autoMigrate: true)`).

### Layer 5 — Sync (offline-first)

```dart
class MyBackendSyncProvider implements SyncProvider {
  @override
  Future<SyncResult> push(SyncOp op) async { /* ... */ }

  @override
  Stream<SyncOp> pull() async* { /* ... */ }
}

final sync = MyBackendSyncProvider(...);
sync.attach(db);
```

The local SQLite database is the source of truth for reads. Push
to the server happens in the background; the user sees consistent,
fast, local data on every device, online or offline. The queue is
persisted to a `d_rocket_sync_queue` table — a crash mid-sync does
not lose queued changes.

### Layer 6 — Realtime

```dart
@WebSocketRoute(url: 'wss://api.example.com/realtime')
abstract class RealtimeClient {
  @WebSocketMethod('/orders')
  Stream<Order> watchOrders();
}

final realtime = dRealtime.create<RealtimeClient>(config: WebSocketConfig(
  url: 'wss://api.example.com/realtime',
));

realtime.watchOrders().listen((order) {
  print('order update: ${order.id}');
});
```

Reconnection with exponential backoff and a heartbeat are automatic.

---

## Migrations

d_rocket has two complementary migration systems:

**Hand-written (pre-1.2.0):** code-first migrations declared as
`MigrationBase` subclasses, run by `MigrationRunner`, tracked in a
`_d_rocket_migrations` table. The dev writes the `up` and `down`
bodies explicitly.

**Auto (1.2.0+):** when `Db.open(entityMetas: [...], autoMigrate: true)`
is set, d_rocket computes the diff between the codegen-emitted
schema and the last applied snapshot (stored in a
`d_rocket_schema_state` table). Safe operations (CREATE TABLE /
CREATE INDEX / ADD COLUMN nullable or with default) are applied in
a single transaction; unsafe operations (DROP TABLE / DROP COLUMN /
DROP INDEX / MODIFY COLUMN) are reported via
`db.pendingSchemaDiff()` and are **never** auto-applied. The user
handles the unsafe changes explicitly (typically by writing a
hand-rolled migration that performs the drop or type change).

The two systems coexist: hand-written migrations run first, then
auto-migration runs. A project that started with hand-written
migrations can opt into auto-migration for the steady-state
add-column / add-index work without rewriting the initial schema.

For the full design, see the
[Migrations guide](https://github.com/torogoz-tech/d_rocket/blob/main/doc/10-migrations.md)
and the
[FAQ — Auto-migrations](https://github.com/torogoz-tech/d_rocket/blob/main/doc/13-faq.md#auto-migrations-120).

---

## Codegen

`d_rocket_builder` runs under `build_runner` and emits:

- `*.d_rocket_serializer.g.dart` — per-class `fromJson` / `toJson`
  + central `register<X>Serializer` calls.
- `*.d_rocket_rest_client.g.dart` — per-interface `RestClient`
  implementations with interceptors, retry, and serialization wired
  in.
- `*.d_rocket_table.g.dart` — per-`@Table` class: `entityMeta`
  constant, `EntityRegistry` registration, `DbSet<T>` accessor.
- `d_rocket_registry.g.dart` — the central `initializeD()` that
  registers every `@Serializable`, `@RestClient`, and `@Table`
  in the project.

One `dart run build_runner build` after every schema or API change.

---

## Platform support

| Platform | Supported? | Why |
|---|---|---|
| **Android** | ✅ | `dart:ffi` + `package:sqlite3` (libsqlite3 bundled). |
| **iOS** | ✅ | Same. |
| **Linux** | ✅ | Same. |
| **macOS** | ✅ | Same. |
| **Windows** | ✅ | Same. |
| **Web (JS / WASM)** | ❌ | The `sqlite3` dependency is a thin Dart wrapper over `dart:ffi`, which the Dart-to-JS compiler does not support. There is no `dart:ffi` on the Web target. The runtime and the LINQ provider (`IQueryable<T>`, serialization, REST client, sync, realtime) are platform-neutral and work everywhere; only the **ORM / persistence** layer (Layer 4) is Web-incompatible. |

If you need a Web target, use the other five layers (1, 2, 3, 5, 6)
and bring your own storage (IndexedDB, OPFS, sql.js, etc.).

Web support is on the roadmap for a future major release.

---

## Project layout

```
packages/
  d_rocket/                  ← runtime (this package)
    lib/
      d_rocket.dart          ← public barrel
      src/
        serializer/          ← Layer 1
        rest/                ← Layer 2
        linq/                ← Layer 3
        sqlite/              ← Layer 4 (engine)
        orm/                 ← Layer 4 (context, migrations, auto-migrations)
        sync/                ← Layer 5
        realtime/            ← Layer 6
    bin/
      migration.dart         ← `d_rocket:migration` CLI scaffolder
      closure.dart           ← `d_rocket:closure` CLI helper
  d_rocket_builder/          ← codegen (`build_runner` integration)
                              ships 5 builders (serializer, rest_client,
                              table, registry, custom lints)
```

## Documentation

The README is the landing page. The full reference lives in the
[`doc/`](https://github.com/torogoz-tech/d_rocket/blob/main/doc/)
folder of the source repository (it is **not** part of the
published package; `pub publish` only ships `lib/`, `bin/`,
`README.md`, `CHANGELOG.md`, and `LICENSE`).

Start here:

- [STATUS](https://github.com/torogoz-tech/d_rocket/blob/main/doc/STATUS.md)
  — one-page snapshot: features, providers, tests, links.
- [Overview](https://github.com/torogoz-tech/d_rocket/blob/main/doc/01-overview.md) — what `d_rocket` is, the six layers, and the design philosophy.
- [Quickstart](https://github.com/torogoz-tech/d_rocket/blob/main/doc/02-quickstart.md) — five minutes from `pubspec.yaml` to a working query.
- [Installation](https://github.com/torogoz-tech/d_rocket/blob/main/doc/03-installation.md) — pubspec config, build_runner, platform-specific setup.
- [Layer 1 — Serialization](https://github.com/torogoz-tech/d_rocket/blob/main/doc/04-layer-1-serialization.md)
- [Layer 2 — REST](https://github.com/torogoz-tech/d_rocket/blob/main/doc/05-layer-2-rest.md)
- [Layer 3 — LINQ](https://github.com/torogoz-tech/d_rocket/blob/main/doc/06-layer-3-linq.md)
- [Layer 4 — ORM (SQLite)](https://github.com/torogoz-tech/d_rocket/blob/main/doc/07-layer-4-orm.md)
- [Layer 5 — Sync](https://github.com/torogoz-tech/d_rocket/blob/main/doc/08-layer-5-sync.md)
- [Layer 6 — Realtime](https://github.com/torogoz-tech/d_rocket/blob/main/doc/09-layer-6-realtime.md)
- [Migrations](https://github.com/torogoz-tech/d_rocket/blob/main/doc/10-migrations.md) — code-first, auto-migrations, and the mix.
- [CLI tools](https://github.com/torogoz-tech/d_rocket/blob/main/doc/11-cli.md) — `d_rocket:migration` and `d_rocket:closure`.
- [Cookbook](https://github.com/torogoz-tech/d_rocket/blob/main/doc/12-cookbook.md) — real recipes (auth, pagination, multi-tenant, FTS, soft delete, encryption).
- [FAQ](https://github.com/torogoz-tech/d_rocket/blob/main/doc/13-faq.md) — common questions and the auto-migrations guide.
- [Architecture](https://github.com/torogoz-tech/d_rocket/blob/main/doc/14-architecture.md) — internal design, codegen pipeline, extension points.

## Status (2026-06-15)

| Metric | Value |
|---|---|
| Latest release | 1.2.0 (auto-migrations) |
| Previous release | 1.1.1 (sync queue persistence + FK enforcement) |
| Tests | 857 pass + 1 skip (libsqlcipher) |
| Analyzer warnings | 0 |
| pana score | 140/160 (gap: Web platform not supported, custom lint dependency on `custom_lint_builder 0.8.1` caps `analyzer` at `^8.0.0`) |
| Public packages on pub.dev | `d_rocket`, `d_rocket_builder` |
| Lockstep versioning | yes, since 1.1.1 |

## What's in (1.1.1, 1.2.0)

- Persistent sync queue (1.1.1) — `d_rocket_sync_queue` table, atomic with the data write.
- FK enforcement on by default (1.1.1) — `PRAGMA foreign_keys = ON` on every open.
- Codegen `CREATE INDEX` + `@Column(isForeignKey: true)` emits `REFERENCES` (1.1.1).
- Auto-migrations (1.2.0) — schema diff, safe operations applied in a tx, unsafe reported.
- New public API: `Db.runAutoMigrations()`, `Db.pendingSchemaDiff()`.

## What's on deck (1.3.0 candidates)

- **REST "esteroides"** (rate limit + circuit breaker + cache wrap-around) — partially implemented; the wrap-around cache is missing.
- **PostgreSQL integration tests** via testcontainers — the Postgres provider is shipped but untested against a live server.
- **Missing LINQ operators** (selectMany_, toLookup_, reverse_, defaultIfEmpty_, zip_, sequenceEqual_) — 1.3.0 should close the gap.
- **CLI scaffolder for migrations** (`dart run d_rocket:migration add "name"`) — the bin/ exists but is minimal; 1.3.0 should make it EF Core parity.
- **Mark the 4 legacy packages as `discontinued` on pub.dev** (1-day task).
- **Codegen split** (move `d_rocket_lints` out of `d_rocket_builder` so the main codegen can bump `analyzer` to `^13.0.0`).

## Support

- **Docs**: [github.com/torogoz-tech/d_rocket](https://github.com/torogoz-tech/d_rocket)
- **Issues**: [github.com/torogoz-tech/d_rocket/issues](https://github.com/torogoz-tech/d_rocket/issues)
- **Discussions**: [github.com/torogoz-tech/d_rocket/discussions](https://github.com/torogoz-tech/d_rocket/discussions)

## License

© Torogoz Tech. Released under the [MIT License](LICENSE).
