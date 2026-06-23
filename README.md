# d_rocket

> Dart's data rocket — serialize, query, persist, sync.

<p align="center">
  <img src="https://coresg-normal.trae.ai/api/ide/v1/text_to_image?prompt=A%20modern%2C%20sleek%20rocket%20launching%20through%20a%20stylized%20database%20disk%2C%20with%20a%20trail%20of%20code%20streams%20representing%20six%20layers%20%28serialization%2C%20REST%2C%20LINQ%2C%20ORM%2C%20sync%2C%20realtime%29%2C%20deep%20navy%20blue%20to%20electric%20cyan%20gradient%2C%20geometric%20hexagonal%20accents%2C%20professional%20Dart%20framework%20brand%20banner%2C%20clean%20composition%2C%20no%20text&image_size=landscape_16_9" alt="d_rocket banner" width="100%">
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

part 'app.g.dart';

@Table()
class User {
  @PrimaryKey(autoIncrement: true) late int id;
  @Column() late String name;
}

// Boot the engine once at app startup.
void main() async {
  dRocketSqlite();
  initializeD();
  final db = await Db.open(path: 'app.db');
  // Use the registered table context.
  await db.tables.insert(
    (db.tables.entityMetaFor(User).newRow() as User)..name = 'alice',
  );
}
```

> **Note:** the actual `Db.insert` API uses the entity's
> generated `newRow()` helper, not a hand-built constructor.
> See [d_rocket/doc/04-layer-1-serialization.md](https://github.com/torogoz-tech/d_rocket/blob/main/doc/04-layer-1-serialization.md)
> for the full pattern.

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
