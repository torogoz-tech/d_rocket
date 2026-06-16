# 🚀 d_rocket

> **Dart's data rocket — serialize, query, persist.**

`d_rocket` is a single-package framework for the data layer of Dart and
Flutter applications. It unifies the six concerns that, in most stacks,
force you to glue together half a dozen different libraries:

| Layer | What you get |
|---|---|
| **1 — Serialization** | `@Serializable` classes with type-safe `fromJson` / `toJson`, union types, custom formatters, and policies for unknown keys. |
| **2 — REST** | `@RestClient` interfaces with retry, backoff, rate limiting, circuit breaker, response cache, and a full interceptor chain. |
| **3 — LINQ** | Deferred-execution `IQueryable<T>` with 40+ operators: filter, project, group, join, aggregate, set, quantifier, element, page. |
| **4 — ORM (SQLite)** | `DbContext`, change-tracked `DbSet<T>`, code-first migrations, `saveChanges()`, eager-loading `include_<T>()`, reactive `watch()`. |
| **5 — Sync (offline-first)** | `SyncProvider` interface, `SyncOp` queue with persistence, push / pull pipelines, conflict-resolution policies. |
| **6 — Realtime** | `@WebSocketRoute` and `@SseRoute`, typed `Stream<T>`, reconnection with exponential backoff, heartbeat. |

All six layers share a build-time **codegen** package
([`d_rocket_builder`](https://pub.dev/packages/d_rocket_builder)) that
wires the whole thing up with a single `initializeD()` call.

```dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';

void main() async {
  initializeD();
  final db = await Db.open(path: 'app.db');
  db.set<Todo>().add(Todo(id: 1, title: 'Ship d_rocket 1.0'));
  await db.saveChanges();
  final pending = await db.set<Todo>()
      .where_(t => t.done == false)
      .toListAsync_();
  print('${pending.length} pending todos');
}
```

---

## Platform support

`d_rocket` is **not** a Web package.

| Platform | Supported? | Why |
|---|---|---|
| **Android** | ✅ | Uses `dart:ffi` + `package:sqlite3` (libsqlite3 bundled). |
| **iOS** | ✅ | Same. |
| **Linux** | ✅ | Same. |
| **macOS** | ✅ | Same. |
| **Windows** | ✅ | Same. |
| **Web** | ❌ | The `sqlite3` dependency is a thin Dart wrapper over `dart:ffi`, which the Dart-to-JS compiler does not support. There is no `dart:ffi` on the Web target, and WASM-on-Web is not yet a first-class FFI host. |

The decision is deliberate: `d_rocket`'s ORM layer is built around
the SQLite C API for performance and SQL-feature parity, and shelling
out to a JS-only SQLite (sql.js / wa-sqlite) from Dart-on-Web would
require a `dart:js_interop` adapter that the package does not
currently ship. The runtime and the LINQ provider (`IQueryable<T>`,
serialization, REST client, sync, realtime) are platform-neutral and
work everywhere; only the **ORM / persistence** layer (Layer 4) is
Web-incompatible.

If you need a Web target, use the other five layers (1, 2, 3, 5, 6)
and bring your own storage (IndexedDB, OPFS, sql.js, etc.).

Web support is on the roadmap for a future major release (planned
v1.1 or v2.0). See the `Roadmap` section below.

---

## Breaking changes in v1.0 — the rename

d_rocket v1.0 drops the `Rocket` prefix from every public
type and from every CLI command name. The change is
mechanical, but it does mean three new things to be
aware of:

| Was | Is now |
|---|---|
| `class Book extends RocketTable { ... }` | `class Book extends Table { ... }` |
| `class MyDb extends RocketDbContext { ... }` | `class MyDb extends DbContext { ... }` |
| `class MyDb extends RocketDb { ... }` | `class MyDb extends Db { ... }` |
| `@RocketTable` | `@Table` |
| `@RocketMigration` | `@Migration` (the codegen still emits a `MigrationBase` subclass; see below) |
| `RocketMigration` (the annotation class) | `Migration` |
| `RocketMigration` (the abstract base) | `MigrationBase` |
| `d_rocket:rocket_migration` (CLI) | `d_rocket:migration` (CLI) |
| `d_rocket:rocket_closure` (CLI) | `d_rocket:closure` (CLI) |
| `d_rocket:rocket_table` (codegen target) | `d_rocket:table` (codegen target) |
| `rocketDb()`, `rocketRegistry()`, `rocketSerializer()` (init helpers) | `db()`, `registry()`, `serializer()` |

The two notable exceptions to the "drop the prefix"
rule are:

* **`@Table`** — the annotation. The codegen reads
  `@Table` on a class and emits a `Table`-based
  registry entry. There is no `class Table` that the
  user extends for the table itself (the user's class
  is just a plain Dart class that extends `Table` to
  opt in to the metadata).
* **`@Migration`** vs **`MigrationBase`** — the
  *annotation* is `Migration` (used as
  `@Migration(id: '001', name: '...')`); the
  *abstract base* that the codegen-emitted migration
  subclass extends is `MigrationBase`. The two names
  are deliberately distinct to avoid a same-library
  class-name collision: the user writes
  `@Migration(...) MigrationBase fn => _$_fn;` and
  the codegen emits `_$_fn extends MigrationBase`.

### Clashes with your own code

`Table`, `Model`, `Migration`, and `DbContext` are
common class names. If your domain model has its own
`class Table` (e.g. a UI data grid wrapper), your
`class Book extends Table` will now resolve to
**d_rocket's** `Table`, not yours. Three ways to
handle this:

```dart
// (a) Use a prefix at import time:
import 'package:d_rocket/d_rocket.dart' as d_rocket;
// then write d_rocket.Table in your code, and your
// local Table keeps its identity.

// (b) Hide the clashing names from d_rocket:
import 'package:d_rocket/d_rocket.dart' hide Table, DbContext;
// useful if you only need a subset of d_rocket
// symbols.

// (c) Use show to take only what you need:
import 'package:d_rocket/d_rocket.dart' show DbContext, DbSet;
// and your local Table stays unshadowed.
```

The same three patterns apply to `DbContext`,
`Migration`, `MigrationBase`, `Db`, `Model`, and any
other d_rocket type that you happen to have locally.

### Migration codegen output

If you used `d_rocket_builder` with the old names,
your `*.d_rocket_orm.g.dart` files will need a fresh
build. Run:

```bash
dart run build_runner build --delete-conflicting-outputs
```

The codegen will emit the new names automatically.
There is no source-level change in your hand-written
classes — the codegen output is regenerated from
scratch on every build.

### CHANGELOG

See [`CHANGELOG.md`](./CHANGELOG.md) for the full
1.0.0 entry, which lists the rename alongside the
other v1.0 changes.

---

## Table of contents

- [Platform support](#platform-support)
- [Breaking changes in v1.0 — the rename](#breaking-changes-in-v10--the-rename)
- [Why d_rocket?](#why-d_rocket)
- [Installation](#installation)
- [Quickstart](#quickstart)
- [Layer 1 — Serialization](#layer-1--serialization)
- [Layer 2 — REST clients](#layer-2--rest-clients)
- [Layer 3 — LINQ queries](#layer-3--linq-queries)
- [Layer 4 — ORM (SQLite)](#layer-4--orm-sqlite)
- [Layer 5 — Sync (offline-first)](#layer-5--sync-offline-first)
- [Layer 6 — Realtime](#layer-6--realtime)
- [Migrations](#migrations)
- [Codegen](#codegen)
- [Platforms](#platforms)
- [Project layout](#project-layout)
- [Documentation](#documentation)
- [Roadmap](#roadmap)
- [Support](#support)
- [License](#license)

---

## Why d_rocket?

Most Dart/Flutter apps assemble their data layer from a constellation of
packages: one for JSON, another for HTTP, a third for SQLite, a fourth
for migrations, a fifth for offline sync, and a half-dozen glue files
that wire it all up. Each one has its own annotation style, its own
error model, its own dialect.

`d_rocket` replaces that with **one package, one mental model, one
generator**:

- **Annotation-driven.** Mark a class with `@Serializable`, an interface
  with `@RestClient`, an entity with `@RocketTable`. The generator
  produces the wiring; you write the model.
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
  stack. The engine library is a consumer choice (see
  [Security — encrypted databases](doc/13-faq.md#how-do-i-open-an-encrypted-database)).
- **Production-tested.** 821 unit and integration tests cover all four
  layers and the codegen pipeline.

## Installation

Add the runtime and the codegen to your `pubspec.yaml`:

```yaml
dependencies:
  d_rocket: ^1.0.0

dev_dependencies:
  d_rocket_builder: ^1.0.0
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

@RocketTable('todos')
class Todo {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final String title;
  @Column() final bool done;
  Todo({this.id = 0, required this.title, this.done = false});
}

void main() async {
  // 1. Wire every @Serializable / @RestClient / @RocketTable
  //    in the project with one call.
  initializeD();

  // 2. Open a local SQLite database. The migrations list
  //    is applied automatically on first run.
  final db = await RocketDb.open(
    path: 'app.db',
    strategy: MigrationStrategy(
      version: 1,
      migrations: [
        M001CreateTodos(),
      ],
    ),
  );

  // 3. Insert.
  db.set<Todo>().add(Todo(title: 'Ship 1.0'));
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

The example above assumes a `M001CreateTodos` migration class. The
[Migrations](#migrations) section below shows what that looks like.

---

## Layer 1 — Serialization

Mark a class with `@Serializable` and the generator emits a
`fromJson` constructor, a `toJson` method, and registers the
serializer with the central `initializeD()` dispatcher.

```dart
@Serializable()
class Customer {
  Customer({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;
}

// Generated.
final json = customer.toJson();
final back = Customer.fromJson(json);
final List<Customer> list = Serializer.fromJson<List<Customer>>(rawJson);
```

**Naming policy** — wire format doesn't have to match your Dart field
names:

```dart
@Serializable(jsonNaming: JsonNaming.snakeCase)
class Product {
  final String productName;     // <-> product_name on the wire
  final double unitPriceUsd;    // <-> unit_price_usd
}
```

**Unknown keys** — three modes: `ignore` (default, drop silently),
`strict` (throw on extras), `capture` (route extras to a
`Map<String, Object?> extra` field).

**Sealed unions** — for sum types, use `@SerializableUnion()`. The
dispatcher reads a discriminator field and returns the right subtype.

See the [Serialization guide](https://github.com/torogoz-tech/d_rocket/blob/main/doc/04-layer-1-serialization.md)
for the full surface (custom formatters, `Format` enum, `JsonKey`,
union dispatch).

## Layer 2 — REST clients

Define an abstract interface, annotate methods with HTTP verbs. The
generator produces a fully-wired client behind a typed signature.

```dart
@RestClient(baseUrl: 'https://api.example.com/v1')
abstract class ShopClient {
  @HttpGet('/products')
  Future<List<Product>> listProducts(@Query('category') String? category);

  @HttpGet('/products/{id}')
  Future<Product> getProduct(@Path('id') int id);

  @HttpPost('/orders')
  Future<Order> createOrder(@Body() OrderDraft draft);

  @HttpDelete('/orders/{id}')
  Future<void> cancelOrder(@Path('id') int id);
}
```

**Resilience** — retry, rate limit, circuit breaker, response cache,
all configured in one place:

```dart
final client = dRest.create<ShopClient>(
  config: RestConfig(
    baseUrl: 'https://api.example.com/v1',
    retry: RetryPolicy(
      maxAttempts: 4,
      backoff: Backoff.exponential(base: Duration(milliseconds: 200)),
    ),
    circuitBreaker: CircuitBreaker(
      failureThreshold: 5,
      openDuration: Duration(seconds: 30),
    ),
  ),
);
```

**Interceptors** — auth tokens, logging, tracing, metrics — register
once, apply to every request:

```dart
dRest.use(AuthInterceptor(loadToken()));
dRest.use(LoggingInterceptor());
```

See the [REST guide](https://github.com/torogoz-tech/d_rocket/blob/main/doc/05-layer-2-rest.md)
for the full surface (`CancelToken`, mock clients, error mapping,
streaming).

## Layer 3 — LINQ queries

Deferred-execution queries that work over in-memory lists, JSON
arrays, and database tables. The expression tree is the same in all
three cases.

```dart
// 1. Compose the query (a recipe, not a result).
final expensive = products
    .asQueryable()
    .where_(p => p.category == 'electronics')
    .where_(p => p.price > 50)
    .orderByDescending_(p => p.price)
    .take_(10);

// 2. Run it once, when you need the values.
final top = await expensive.toListAsync_();
```

40+ operators across filter, project, page, order, set, quantifier,
aggregate, element, convert, join, and group. See the
[LINQ reference](https://github.com/torogoz-tech/d_rocket/blob/main/doc/06-layer-3-linq.md)
for the complete matrix.

**Push-down to SQL** — when the source is a `DbSet<T>`, the same
operators become SQL. No second query language to learn:

```dart
final avg = await db.set<Product>()
    .where_(p => p.category == 'electronics')
    .average_(p => p.price);
// => SELECT AVG(price) FROM products WHERE category = 'electronics'
```

## Layer 4 — ORM (SQLite)

`@RocketTable` defines a row. `RocketDb` opens the file.
`DbSet<T>` is your typed table handle. `saveChanges()` commits
inserts, updates, and deletes in a single transaction.

```dart
@RocketTable('orders')
class Order {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final int customerId;
  @Column() final double total;
  @Column() final String status;            // pending / paid / shipped
  @Column(name: 'placed_at') final DateTime placedAt;
  @BelongsTo('customer', Customer) Customer? customer;
  @HasMany('order', LineItem) List<LineItem> items = [];
}

// Insert
db.set<Order>().add(order);

// Update
db.set<Order>().updateWhere(
  o => o.id == 42,
  (o) => o.copyWith(status: 'paid'),
);

// Delete
db.set<Order>().removeWhere(o => o.status == 'cancelled');

// Commit (single transaction)
final int affected = await db.saveChanges();
```

**Includes** — load an order with its customer and line items in
one round-trip:

```dart
final order = await db.set<Order>()
    .include_<Customer>()
    .include_<LineItem>()
    .firstOrDefaultAsync_(o => o.id == 42);
```

**Reactive queries** — `watch()` returns a `Stream` that re-emits
when the underlying table changes:

```dart
db.set<Product>()
    .where_(p => p.stockQty > 0)
    .orderBy_(p => p.name)
    .watch();
```

## Migrations

Code-first. Write a `Migration` subclass; the runner tracks which
ones have been applied in a `_d_rocket_migrations` table.

```dart
class M001CreateTodos extends Migration {
  @override
  String get id => '001';
  @override
  int get version => 1;
  @override
  String get name => 'create_todos';

  @override
  void up(MigrationExecutor exec) {
    exec('''
      CREATE TABLE todos (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT    NOT NULL,
        done  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE todos');
  }
}
```

For version-tagged schema management, use `MigrationStrategy`:

```dart
await RocketDb.open(
  path: 'app.db',
  strategy: MigrationStrategy(
    version: 4,
    migrations: [
      M001CreateTodos(),
      M002AddTodosDueDate(),
      M003CreateCustomers(),
      M004CreateOrders(),
    ],
  ),
);
```

The runner inspects the database's current version and either applies
the upgrade subset, rolls back the downgrade subset, or is a no-op.

**CLI scaffolder:**

```bash
$ dart run d_rocket:rocket_migration add create_inventory_table
✅ Created lib/db/migrations/M005_create_inventory_table.dart
   id: 005, class: M005CreateInventoryTable
$ dart run d_rocket:rocket_migration doctor
✅ Migration history is contiguous (5 migrations).
```

## Layer 5 — Sync (offline-first)

`SyncProvider` is the interface your backend integration implements.
The runtime persists `SyncOp`s to the local SQLite database, runs
them through a push pipeline, and listens to a pull pipeline for
server-side changes. Conflict resolution is pluggable.

```dart
class MyBackendSyncProvider implements SyncProvider {
  @override
  Future<SyncResult> push(SyncOp op) async { /* ... */ }

  @override
  Stream<SyncOp> pull() async* {
    while (true) {
      for (final op in await _fetchSince(lastCursor)) {
        yield op;
      }
      await Future.delayed(Duration(seconds: 5));
    }
  }

  @override
  Future<SyncOp> resolveConflict(SyncOp l, SyncOp s, ConflictContext c) async {
    return l.lastAttempt!.isAfter(s.lastAttempt!) ? l : s;
  }
}

final sync = MyBackendSyncProvider(...);
sync.attach(db);
```

The local SQLite database is the source of truth for reads. Push
to the server happens in the background; the user sees consistent,
fast, local data on every device, online or offline.

## Layer 6 — Realtime

Typed `WebSocket` and `Server-Sent Events` clients with codegen.
Annotate a method with `@WebSocketRoute` or `@SseRoute`, get a
`Stream<T>` back. Reconnection with exponential backoff and a
heartbeat are automatic.

```dart
@WebSocketRoute(url: 'wss://api.example.com/realtime')
abstract class RealtimeClient {
  @WebSocketMethod('/orders')
  Stream<Order> watchOrders();

  @WebSocketMethod('/orders/{id}')
  Stream<OrderEvent> watchOrder(@Path('id') int id);
}

final realtime = dRealtime.create<RealtimeClient>(config: WebSocketConfig(
  url: 'wss://api.example.com/realtime',
));

realtime.watchOrders().listen((order) {
  print('order update: ${order.id}');
});
```

The same JSON serializer from Layer 1 is reused for inbound and
outbound payloads.

## Codegen

`d_rocket_builder` runs under `build_runner` and emits:

- `*.d_rocket_serializer.g.dart` — per-class `fromJson` / `toJson`
  + central `register<X>Serializer` calls.
- `*.d_rocket_rest_client.g.dart` — per-interface `RestClient`
  implementations with interceptors, retry, and serialization wired
  in.
- `d_rocket_registry.g.dart` — the central `initializeD()` that
  registers every `@Serializable`, `@RestClient`, and
  `@RocketTable` in the project.

One `dart run build_runner build` after every schema or API change.

## Platforms

| Platform | Status |
|---|---|
| Android | ✅ |
| iOS | ✅ |
| macOS | ✅ |
| Windows | ✅ |
| Linux | ✅ |
| Web (JS) | ⚠️ SQLite is not available; use an in-memory `RocketDb` for tests |

The framework itself is platform-agnostic; the SQLite engine is the
only platform-specific dependency (`package:sqlite3`).

## Project layout

```
packages/
  d_rocket/                  ← runtime (this package)
    lib/
      d_rocket.dart          ← public barrel
      src/
        linq/                ← Layer 3
        serializer/          ← Layer 1
        rest/                ← Layer 2
        sqlite/              ← Layer 4 (engine)
        orm/                 ← Layer 4 (context, migrations)
        sync/                ← Layer 5
        realtime/            ← Layer 6
    bin/
      rocket_migration.dart  ← `d_rocket:rocket_migration` CLI
  d_rocket_builder/          ← codegen (`build_runner` integration)
  d_rocket_provider_sqlite/  ← legacy thin wrapper (use `d_rocket` directly)
```

## Documentation

The README is the landing page. The full reference
lives in the [`doc/`](https://github.com/torogoz-tech/d_rocket/blob/main/doc/)
folder of the source repository (it is **not** part
of the published package; `pub publish` only ships
`lib/`, `bin/`, `README.md`, `CHANGELOG.md`, and
`LICENSE`).

Start here:

- [Overview](https://github.com/torogoz-tech/d_rocket/blob/main/doc/01-overview.md) — what `d_rocket` is, the six layers, and the design philosophy.
- [Quickstart](https://github.com/torogoz-tech/d_rocket/blob/main/doc/02-quickstart.md) — five minutes from `pubspec.yaml` to a working query.
- [Installation](https://github.com/torogoz-tech/d_rocket/blob/main/doc/03-installation.md) — pubspec config, build_runner, platform-specific setup.
- [Layer 1 — Serialization](https://github.com/torogoz-tech/d_rocket/blob/main/doc/04-layer-1-serialization.md) — `@Serializable`, `JsonNaming`, sealed unions.
- [Layer 2 — REST](https://github.com/torogoz-tech/d_rocket/blob/main/doc/05-layer-2-rest.md) — `@RestClient`, resilience, interceptors.
- [Layer 3 — LINQ](https://github.com/torogoz-tech/d_rocket/blob/main/doc/06-layer-3-linq.md) — `IQueryable<T>`, every operator, SQL push-down.
- [Layer 4 — ORM (SQLite)](https://github.com/torogoz-tech/d_rocket/blob/main/doc/07-layer-4-orm.md) — `@Table`, `DbSet<T>`, change tracking, includes, watch.
- [Layer 5 — Sync](https://github.com/torogoz-tech/d_rocket/blob/main/doc/08-layer-5-sync.md) — `SyncProvider`, push / pull, conflict resolution.
- [Layer 6 — Realtime](https://github.com/torogoz-tech/d_rocket/blob/main/doc/09-layer-6-realtime.md) — `@WebSocketRoute`, `@SseRoute`, reconnection.
- [Migrations](https://github.com/torogoz-tech/d_rocket/blob/main/doc/10-migrations.md) — `Migration` base class, `MigrationStrategy`, CLI scaffolder.
- [CLI tools](https://github.com/torogoz-tech/d_rocket/blob/main/doc/11-cli.md) — `d_rocket:migration` and `d_rocket:closure`.
- [Cookbook](https://github.com/torogoz-tech/d_rocket/blob/main/doc/12-cookbook.md) — real recipes (auth, pagination, multi-tenant, FTS, soft delete, encryption, etc.).
- [FAQ](https://github.com/torogoz-tech/d_rocket/blob/main/doc/13-faq.md) — common questions and migration notes.
- [Architecture](https://github.com/torogoz-tech/d_rocket/blob/main/doc/14-architecture.md) — internal design, codegen pipeline, extension points.

## Roadmap

These are directions the maintainers are **actively exploring**
for the next minor releases. None of these are firm
commitments — they are areas where the design space is being
investigated. Items in `considered` may be deferred or
dropped; items in `in design` have a proposed shape; items
in `prototyping` have working code in a feature branch.

| Status | Item | Notes |
|---|---|---|
| 🟡 considered | **Web platform provider** (`d_rocket_provider_idb`) | An IndexedDB-backed `AsyncQueryProvider` so the framework runs in the browser. Today the framework is not supported on `flutter web` because `package:sqlite3` is native-only. |
| 🟡 considered | **PostgreSQL provider** (`d_rocket_provider_postgres`) | A server-side `AsyncQueryProvider` for Dart-on-server apps (shelf, etc.). Would let the same `@RocketTable` annotations compile to a Postgres schema. |
| 🟡 considered | **First-class observability hooks** | An `Instrumentation` interface with hooks for tracing (`onQueryStart`, `onQueryEnd`, `onRestCall`, `onSyncOp`, `onReconnect`). Implementations could emit OpenTelemetry spans, log structured events, or push metrics. |
| 🟡 considered | **`ResponseCache` wrap-around client** | A `CachingHttpClient` (alongside `RetryingHttpClient`, `RateLimitedHttpClient`, `CircuitBreakerHttpClient`) that memoizes GET responses by URL + query. The 1.0 doc listed this but the implementation was deferred. |
| 🟡 considered | **Free-standing `Backoff` config class** | Today the backoff parameters are bundled inside `ExponentialBackoffRetryPolicy` (`maxAttempts`, `baseDelay`, `factor`, `maxDelay`, `jitter`). Extracting them into a `Backoff` value object would let users reuse the same backoff curve across multiple policies. |
| 🟡 considered | **Async terminals on `IQueryable<T>`** (`toListAsync_`, `firstAsync_`, `countAsync_`, etc.) | The current design keeps the LINQ chain synchronous and pushes async work into `DbSet` (which has `toListAsync_`, `findByIdAsync`, etc.). Adding `*Async_` variants on `IQueryable` would let users write `await query.where_(...).orderBy_(...).toListAsync_()` end-to-end. |
| 🟡 considered | **Closure-sugar builder** | The canonical form today is explicit `Expr.lambda(...)` chains. A `dart build_runner` builder that rewrites closure calls (`p => p.x == v`) into `Expr` trees at build time would lower the cognitive cost. The runtime contract is already in place; the builder needs to be re-added. |
| 🟡 considered | **WebSocket heartbeat** | The current `WebSocketReconnector` handles the initial connect with exponential backoff; mid-session reconnects are user-driven. A `Heartbeat` (ping frame every N seconds, kill connection if no pong within M seconds) would be a natural addition for long-lived streams. |
| 🟡 considered | **`ChannelWebSocketConnection` for the web** | The `dart:io`-backed `IOWebSocketClient` doesn't run in the browser. A `ChannelWebSocketConnection` wrapping `package:web_socket_channel` would unblock the web for the realtime layer. |
| 🟡 considered | **Boxed `LoggingInterceptor`** | Every consumer re-writes a logging interceptor. Shipping one in the box (configurable, with a sensible default of "method, URL, status, elapsed") would save 30 lines per project. |
| 🟢 in design | **IDE query analyzer** | A `package:custom_lint` rule (alongside `d_rocket_n_plus_one` and `d_rocket_closure`) that surfaces LINQ chains in the editor with red squigglies for queries that won't push-down to SQL. Today those failures only surface at runtime. |
| 🟢 in design | **`@RocketTable` virtual tables / FTS5 helpers** | First-class codegen for `@FullTextIndex` virtual tables and triggers. The raw `@FullTextIndex` annotation exists today but the codegen is currently opt-in via a builder option. |
| 🟢 in design | **`ConflictPolicy` enum (typed, with custom-fn escape hatch)** | Today `ConflictResolver` is a typedef (`Map<String,Object?> Function(local, remote)`); the default is `LwwConflictResolver.instance`. A typed enum (`lww`, `serverWins`, `clientWins`, `custom(fn)`) would be safer-by-default and align with how the v0.x doc described it. |
| 🟢 in design | **`dRest.create<T>(config: ...)` factory** | Today the user constructs clients via the codegen-emitted accessor; `dRest` is a singleton with `useDefaults(...)`. A factory-per-type would let users have multiple clients (e.g. a `ShopClient` and a `PublicApiClient` with different retry policies) without singleton gymnastics. |
| 🟢 in design | **Split `d_rocket_lints` out of `d_rocket_builder`** | Today `d_rocket_builder` ships 3 custom lints (LinqClosureLint, NPlusOneLint, LinqClosureFix) and depends on `custom_lint_builder 0.8.1`, which caps `analyzer` at `^8.0.0`. The lints are a different concern from the codegen — splitting them into a separate `d_rocket_lints` package would let the main codegen bump to `analyzer ^13.0.0` (the current latest) without losing the lints, and would also let users opt in to the lints only if they want them. The blocker for the 1.0 analyzer bump (5 majors behind) is fully solved by this split. |
| 🟢 in design | **`@BelongsTo` and `@HasMany` as explicit annotations** | Today the codegen computes navigations from `@ForeignKey` fields. Explicit annotations would let the user be declarative about cardinality (1:1 vs 1:many) without relying on the codegen to discover it from inverse FKs. |
| 🔵 prototyping | **`d_rocket_admin`** | An auto-generated admin UI for any `@RocketTable` set: list view, create form, edit form, soft delete, with sensible defaults for the `@RocketTable` annotation. Runs as a Flutter app or a web page. |
| 🔵 prototyping | **FFI-backed SQLite engine** | A drop-in `AsyncQueryProvider` that talks to SQLite via dart:ffi instead of `package:sqlite3`'s dynamic loading. ~2× faster for most workloads. Tracked separately so the JS-only provider can stay clean. |
| 🔵 prototyping | **Cap-and-trim policy for `pendingSyncChanges`** | Today the queue is unbounded; a user can manually cap with a `StateError` check. A built-in "drop oldest above N" policy (or a "drop newest above N" variant) would be safer-by-default for long-running offline devices. |

The full tracker is on the
[GitHub Projects board](https://github.com/torogoz-tech/d_rocket/projects).
If you want a feature to ship faster, open a feature request on
[Issues](https://github.com/torogoz-tech/d_rocket/issues) with
the `enhancement` label and a concrete use case — features
with real-world backing get prioritised.

## Support

- **Docs**: [github.com/torogoz-tech/d_rocket](https://github.com/torogoz-tech/d_rocket)
- **Issues**: [github.com/torogoz-tech/d_rocket/issues](https://github.com/torogoz-tech/d_rocket/issues)
- **Discussions**: [github.com/torogoz-tech/d_rocket/discussions](https://github.com/torogoz-tech/d_rocket/discussions)

## License

© Torogoz Tech. Released under the [MIT License](LICENSE).
