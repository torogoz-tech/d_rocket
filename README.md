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
a dozen different libraries:

| Layer | What you get |
|---|---|
| **Serialization** | `@Serializable` classes with type-safe `fromJson` / `toJson`, union types, custom formatters, and policies for unknown keys. |
| **REST** | `@RestClient` interfaces with retry, backoff, rate limiting, circuit breaker, response cache, and a full interceptor chain. |
| **LINQ** | Deferred-execution `Queryable<T>` with 35 operators (filter, project, group, join, aggregate, set, quantifier, element, page). |
| **ORM (engine-agnostic)** | `DbContext`, change-tracked `DbSet<T>`, code-first + auto-migrations, `saveChanges()`, eager-loading `include_<T>()`, reactive `watch()`. |
| **Sync (offline-first)** | `SyncProvider` interface, persistent `SyncOp` queue (survives crashes), push / pull pipelines, conflict-resolution policies. |
| **Realtime** | `@WebSocketRoute` and `@SseRoute`, typed `Stream<T>`, reconnection with exponential backoff, heartbeat. |

## Engines

The DB engine is a separate package. The same `DbContext` /
`DbSet<T>` / LINQ code runs on:

| Engine | Backend | Status |
|---|---|---|
| [`d_rocket_engine_sqlite`](https://pub.dev/packages/d_rocket_engine_sqlite) | `package:sqlite3` | stable |
| [`d_rocket_engine_postgres`](https://pub.dev/packages/d_rocket_engine_postgres) | `package:postgres` (wire protocol) | stable |
| [`d_rocket_engine_web`](https://pub.dev/packages/d_rocket_engine_web) | IndexedDB (via `idb_shim`) | stable |

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

void main() {
  // 1. Register the engine + the domain.
  dRocketSqlite();
  initializeD();

  // 2. Open a connection (in-memory here;
  // use `SqliteQueryProvider.open(path: 'app.db')` for disk).
  final provider = SqliteQueryProvider.inMemory();
  provider.execute('''
    CREATE TABLE books (
      id       INTEGER PRIMARY KEY,
      title    TEXT NOT NULL,
      authorId INTEGER NOT NULL
    )
  ''');

  // 3. INSERT — via a prepared statement.
  final ins = provider.database.prepare(
    'INSERT INTO books (id, title, authorId) VALUES (?, ?, ?)',
  );
  ins.execute([1, 'A Wizard of Earthsea', 1]);
  ins.execute([2, 'The Left Hand of Darkness', 1]);
  ins.close();

  // 4. Build a typed queryable over the table.
  final books = Queryable<Book>(
    provider: provider,
    table: 'books',
    reader: (row) => Book(
      id: row['id']! as int,
      title: row['title']! as String,
      authorId: row['authorId']! as int,
    ),
  );

  // 5. SELECT — deferred-execution LINQ query.
  final titles = books
      .select_<String>((b) => b.title)
      .toList_();
  print(titles);
  // [A Wizard of Earthsea, The Left Hand of Darkness]

  // 6. UPDATE — single row, parameterised.
  provider.execute(
    'UPDATE books SET title = ? WHERE id = ?',
    ['The Farthest Shore', 1],
  );

  // 7. DELETE — by primary key.
  provider.execute(
    'DELETE FROM books WHERE id = ?',
    [2],
  );

  // 8. Confirm the final state.
  final remaining = books.toList_();
  print(remaining.map((b) => b.title));
  // [The Farthest Shore]

  provider.dispose();
}
```

The full surface (`where_`, `orderBy_`, `take_`, `join_`,
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
