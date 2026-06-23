# d_rocket

> Dart's data rocket — serialize, query, persist, sync.

<p align="center">
  <img src="assets/banner.png" alt="d_rocket banner" width="100%">
</p>

[![ci](https://github.com/torogoz-tech/d_rocket/actions/workflows/ci.yml/badge.svg)](https://github.com/torogoz-tech/d_rocket/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/torogoz-tech/d_rocket/branch/main/graph/badge.svg)](https://codecov.io/gh/torogoz-tech/d_rocket)
[![license](https://img.shields.io/github/license/torogoz-tech/d_rocket)](LICENSE)

`d_rocket` is the engine-agnostic core of a single-package framework
for the data layer of Dart and Flutter applications. It unifies the
six concerns that, in most stacks, force you to glue together half
a dozen different libraries.

## The six layers

| # | Layer | What you get | Annotation | Docs |
|---|---|---|---|---|
| 1 | **Serialization** | `@Serializable` classes with type-safe `fromJson` / `toJson`, union types via `@SerializableUnion`, custom formatters, naming policies (`@JsonKey` + `JsonNaming`), and `unknownKeyPolicy` for forward-compat. | `@Serializable` | [doc/04](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/04-layer-1-serialization.md) |
| 2 | **REST** | `@RestClient` interfaces with `@HttpGet`/`@HttpPost`/`@HttpPut`/`@HttpPatch`/`@HttpDelete`/`@HttpHead`, parameter binding via `@Path`/`@Query`/`@Header`/`@Body`/`@Field`/`@Part`/`@RawBody`, **retry** with backoff, **rate limiting**, **circuit breaker**, **response cache**, **streaming** `Stream<T>` endpoints, **cancelable** requests via `CancelToken`, and a full **interceptor chain**. | `@RestClient` | [doc/05](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/05-layer-2-rest.md) |
| 3 | **LINQ** | Deferred-execution `Queryable<T>` with **35+ operators** across filter, project, order, page, group, join, aggregate, set, quantifier, element, convert. Engine-agnostic AST (`Expr.lambda` for SQL push-down). **Both** sync (`*_`) and async (`*Async_`) terminals. | none — `IQueryable<T>` | [doc/06](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/06-layer-3-linq.md) |
| 4 | **ORM** (engine-agnostic) | `DbContext` with change-tracked `DbSet<T>`, code-first + `@Migration` callbacks, **auto-migrator** with `pendingSchemaDiff()`, eager-loading `include_<TNav>()`, reactive `watch()`, `DbInterceptor` chain, `redactPragmaKey` for SQL logging. `saveChanges()` flushes inserts/updates/deletes in a single transaction. | `@Table` + `@PrimaryKey` + `@Column` + `@ForeignKey` + `@Index` + `@Embedded` | [doc/07](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/07-layer-4-orm.md) |
| 5 | **Sync** (offline-first) | `SyncProvider` interface, `RestSyncProvider` HTTP+JSON impl, persistent identity (`clientId` + watermark) that survives process restarts, push + pull pipelines, **conflict resolution** (LWW, server-wins, client-wins, custom callback), triggers (periodic + signal + manual), retry with exponential backoff. | `class SyncProvider` (no annotation) | [doc/08](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/08-layer-5-sync.md) |
| 6 | **Realtime** | `@WebSocketClient` + `@SseClient` codegen → typed `Stream<T>`, reconnection with exponential backoff, **heartbeat / ping**, reuses the Layer 1 JSON serializer for payloads. | `@WebSocketClient` + `@SseClient` | [doc/09](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/doc/09-layer-6-realtime.md) |

A single `initializeD()` call (emitted by `d_rocket_builder` into
`d_rocket_registry.g.dart`) wires every annotated class in your
project. There is no per-file `registerAll()`, no abstract
`AsyncQueryProvider` to wire by hand.

## Engines

The DB engine is a separate package. The same `DbContext` /
`DbSet<T>` / LINQ code runs on:

| Engine | Backend | Status | LINQ surface |
|---|---|---|---|
| [`d_rocket_engine_sqlite`](https://pub.dev/packages/d_rocket_engine_sqlite) | `package:sqlite3` (file or `sqlite::memory:`) | stable | sync + async |
| [`d_rocket_engine_postgres`](https://pub.dev/packages/d_rocket_engine_postgres) | `package:postgres` (wire protocol, no FFI) | stable | async only |
| [`d_rocket_engine_web`](https://pub.dev/packages/d_rocket_engine_web) | IndexedDB via `idb_shim` (browser) | stable | async only |

> **Note:** the engine-agnostic LINQ is provided by `d_rocket`
> core. Each engine supplies a `QueryProvider` (sync, async, or
> both) and a `SqlDialect` so the in-memory `Expr` tree is
> translated to the engine's SQL dialect. SQLite has both sync
> and async; Postgres and Web are async-only.

## Install

```yaml
dependencies:
  d_rocket: ^2.0.0
  d_rocket_engine_sqlite: ^2.0.0   # pick one engine

dev_dependencies:
  d_rocket_builder: ^2.0.0         # code generation
  build_runner: ^4.0.0
```

## Quick start

```dart
import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

// `d_rocket_registry.g.dart` is emitted by
// `dart run build_runner build` from the
// entities you annotate. It exports `initializeD()`.
import 'books.g.dart';

part 'books.g.dart';

// ─── Domain model: a plain class, no `late` fields,
// no annotation noise. The codegen scans for
// `extends Record` and emits a registration
// snippet into `books.g.dart`. ───

class Book extends Record {
  Book({required this.id, required this.title, required this.authorId});
  final int id;
  final String title;
  final int authorId;
}

Future<void> main() async {
  // 1. Register the engine + the domain.
  dRocketSqlite();
  initializeD();

  // 2. Open a connection. `Db.inMemory()` is
  // a convenience for `Db.open(path: 'sqlite::memory:')`.
  final db = await Db.inMemory();

  // 3. Schema (the codegen would do this via
  // auto-migrations; for the bare-bones example
  // we issue raw DDL).
  await db.provider.executeAsync('''
    CREATE TABLE books (
      id       INTEGER PRIMARY KEY,
      title    TEXT NOT NULL,
      authorId INTEGER NOT NULL
    )
  ''');

  // 4. INSERT — stage with `.add()` then flush.
  db.set<Book>().add(
        Book(id: 1, title: 'A Wizard of Earthsea', authorId: 1),
      );
  db.set<Book>().add(
        Book(id: 2, title: 'The Left Hand of Darkness', authorId: 1),
      );
  await db.saveChanges();

  // 5. SELECT — typed LINQ over the change-tracked set.
  final titles = await db.set<Book>()
      .asQueryable()
      .select_<String>((b) => b.title)
      .toListAsync_();
  print(titles);
  // [A Wizard of Earthsea, The Left Hand of Darkness]

  // 6. UPDATE — load, mutate, stage as `markModified`.
  final List<Book> all = await db
      .set<Book>()
      .asQueryable()
      .toListAsync_()
      .then((v) => v.cast<Book>());
  final first = all.firstWhere((b) => b.id == 1);
  first.title = 'The Farthest Shore';
  db.set<Book>().markModified(first);
  await db.saveChanges();

  // 7. DELETE — stage with `.remove()` then flush.
  db.set<Book>().remove(first);
  await db.saveChanges();

  // 8. Final state.
  final remaining = await db.set<Book>()
      .asQueryable()
      .toListAsync_()
      .then((v) => v.cast<Book>());
  print(remaining.map((b) => b.title));
  // [The Left Hand of Darkness]

  await db.close();
}
```

**The high-level write surface on `DbSet<T>` is**:

| Operation | Method | Flush |
|---|---|---|
| Insert | `db.set<T>().add(entity)` | `await db.saveChanges()` |
| Update | `db.set<T>().markModified(entity)` | `await db.saveChanges()` |
| Delete | `db.set<T>().remove(entity)` | `await db.saveChanges()` |
| Direct insert | `await db.set<T>().insertOneAsync(entity)` | n/a |
| Direct update | `await db.set<T>().updateOneAsync(entity, originalValues)` | n/a |
| Direct delete | `await db.set<T>().deleteOneAsync(entity)` | n/a |

The full LINQ surface (`where_`, `orderBy_`, `take_`, `join_`,
`groupBy_`, `aggregate`, …) lives in
`package:d_rocket/d_rocket.dart` and follows the
[deferred-execution LINQ semantics](https://github.com/torogoz-tech/d_rocket/blob/main/doc/02-layer-3-linq.md).
A 35-query worked example is in
[`example/bookstore.dart`](https://github.com/torogoz-tech/d_rocket_engine_sqlite/blob/main/example/bookstore.dart).

## Generated code

`d_rocket_builder` runs under `build_runner` and emits:

- `*.g.dart` for `@Serializable` (`fromJson` / `toJson`)
- `*.g.dart` for `@Table` (entity metas, joins, change tracking)
- `*.rest.g.dart` for `@RestClient` (typed HTTP client)
- `*.migration.g.dart` for migrations (via `d_rocket:migration` CLI)

## CLI

```bash
# Scaffold a new migration from a pending schema diff
dart run d_rocket:migration add add_note_to_patients \
  --db app.db --entities lib/db/entities.dart

# Run the analyzer with d_rocket lints
dart analyze
```

## Documentation

Full documentation lives in the
[monorepo README](https://github.com/torogoz-tech/d_rocket#readme)
and in the
[docs/](https://github.com/torogoz-tech/d_rocket/tree/main/doc)
directory. The package targets Dart 3.6+ and Flutter 3.10+.

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Torogoz Tech.

## Author

**Abner Velasco** — *Arquitecto de Soluciones*

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Abner%20Velasco-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/abnervelasco/)
