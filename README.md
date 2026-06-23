# d_rocket

> Dart's data rocket — serialize, query, persist, sync.

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

part 'app.g.dart';

@Table(name: 'users')
class User {
  @PrimaryKey() late int id;
  @Column() late String name;
}

@Serializable
class _UserDto extends User {}

// Boot the engine once at app startup.
void main() {
  dRocketSqlite();
  runApp(const MyApp());
}

// Use the DbContext for queries.
Future<void> example() async {
  final db = await Db.open(
    connectionString: ':memory:',
    entities: const [User],
  );
  await db.users.insert(User()..id = 1..name = 'alice');
  final users = await db.users.toList();
}
```

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
