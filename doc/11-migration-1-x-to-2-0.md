# Migrating from 1.x to 2.0

> **2.0.0 is a breaking release.** The biggest
> change is the engine split: the SQLite engine
> is no longer bundled inside `d_rocket`; it
> ships as a separate package,
> `d_rocket_engine_sqlite`.
>
> This guide walks through every breaking
> change in 2.0.0, in the order a typical
> app will hit them. The migration is
> mechanical for most projects; expect
> 10–30 minutes of work for a single-platform
> app and 30–60 minutes for a multi-platform
> app with engine-conditional setup.

---

## TL;DR

If your app uses `Db` / `DbContext` / `DbSet` /
`@Table` / auto-migrations, you must:

1. Add `d_rocket_engine_sqlite: ^2.0.0` to
   your `pubspec.yaml` `dependencies`.
2. Call `dRocketSqlite()` once at app
   startup, before the first
   `Db.open` / `Db.inMemory` call.

If your app only uses `@Serializable` /
`@RestClient` / `IQueryable<T>` /
`SyncProvider` / `WebSocketClient`, the
migration is a no-op — your app stops
downloading `libsqlite3` automatically.

---

## Step 1: pubspec

```yaml
# pubspec.yaml — before 2.0
dependencies:
  d_rocket: ^1.2.2
```

```yaml
# pubspec.yaml — 2.0+
dependencies:
  d_rocket: ^2.0.0
  # Add this only if you use the ORM.
  d_rocket_engine_sqlite: ^2.0.0
```

If your app never opens a `Db`, you can omit
`d_rocket_engine_sqlite` entirely. The build
will be smaller by ~500KB on Android, ~700KB
on iOS, and ~1MB on desktop because
`libsqlite3` is no longer in your
`pubspec.lock`.

## Step 2: register the engine at app startup

```dart
// main.dart — before 2.0
import 'package:d_rocket/d_rocket.dart';

Future<void> main() async {
  initializeD();
  final db = await Db.open(path: 'app.db'); // no register needed
  runApp(MyApp(db: db));
}
```

```dart
// main.dart — 2.0+
import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

Future<void> main() async {
  // Required: tells d_rocket which engine to
  // use for Db.open / Db.inMemory. Without
  // this call, the ORM throws a clear
  // "no engine registered" StateError.
  dRocketSqlite();

  initializeD();
  final db = await Db.open(path: 'app.db');
  runApp(MyApp(db: db));
}
```

`dRocketSqlite()` is idempotent — calling
it twice replaces the engine with a fresh
`SqliteEngine` (in practice there's only one
slot, so this is a no-op).

## Step 3: imports

If you previously imported SQLite-specific
classes from `package:d_rocket/d_rocket.dart`,
update the import to
`package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart`:

| 1.x | 2.0 |
| --- | --- |
| `import 'package:d_rocket/d_rocket.dart';` (for `Db`) | `import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';` |
| `import 'package:d_rocket/d_rocket.dart';` (for `SqliteQueryProvider`) | same — re-exported from the engine |
| `import 'package:d_rocket/d_rocket.dart';` (for `EncryptionConfig`) | same — re-exported from the engine |
| `import 'package:d_rocket/d_rocket.dart';` (for `KeyProvider`) | same — re-exported from the engine |

The `d_rocket_engine_sqlite` barrel
re-exports `d_rocket` core, so a single
import gives you the engine, the SQLite-
specific types, and the engine-agnostic
types from d_rocket core (DbContext,
EntityMeta, @Table, ...).

## Step 4: `redactPragmaKey` is in d_rocket core

In 1.x, `redactPragmaKey` was in
`d_rocket/src/sqlite/redact_pragma_key.dart`
and exported through
`package:d_rocket/d_rocket.dart`. In 2.0, the
function is in d_rocket core
(`d_rocket/src/redact_pragma_key.dart`) and
re-exported from the barrel.

**No code change required.** The import
path is the same
(`package:d_rocket/d_rocket.dart`); the
function's behavior is unchanged.

## Step 5: `DbEngine` and `EngineRegistry` (advanced)

If your code does not interact with
`DbEngine` / `EngineRegistry` directly
(most apps don't), you can skip this step.
Otherwise:

* `EngineRegistry.register(engine)` replaces
  any previously registered engine. Calling
  it twice with two different engines swaps
  the active one. Calling it twice with the
  same engine is a no-op.
* `EngineRegistry.findOrThrow` throws
  `StateError` with an actionable message
  if no engine is registered. The 1.x
  behavior (auto-register a `SqliteEngine`)
  is gone; 2.0 requires explicit
  registration.
* `DbEngine.open()` takes
  `encryptionConfig: Object?` (1.x took
  `EncryptionConfig?`). This makes
  `DbEngine` engine-agnostic; engines
  cast to their expected config type. The
  `Db` facade in `d_rocket_engine_sqlite`
  continues to take `EncryptionConfig?` for
  developer ergonomics.

## Step 6: tests

If your tests use `Db.open` /
`Db.inMemory` / `SqliteQueryProvider` /
`EncryptionConfig`, you must call
`dRocketSqlite()` once at the start of each
test file. Two patterns are supported:

```dart
// Pattern A: one engine for all tests in
// the file (cheaper, but the engine leaks
// between tests).
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(dRocketSqlite);

  test('something', () async {
    final db = await Db.inMemory();
    // ...
  });
}
```

```dart
// Pattern B: fresh engine per test
// (more robust; the engine is reset
// between tests).
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);

  test('something', () async {
    final db = await Db.inMemory();
    // ...
  });
}
```

`d_rocket/test/_helpers.dart` and
`d_rocket_engine_sqlite/test/_helpers.dart`
both export `setUpSqlite()` which is a thin
wrapper around the same logic.

## What if I don't use the ORM?

You don't need to do anything. Your app
stops downloading `libsqlite3`; everything
else works the same way. The
`d_rocket:migration` CLI still has
`d_rocket_engine_sqlite` as a transitive
dep (because the `run` / `status` /
`rollback` subcommands need a real
engine), but you only pay the cost if you
run those subcommands.

## Future: Postgres + libsql_wasm

When
[`d_rocket_engine_postgres`](../d_rocket_engine_postgres/README.md)
and
[`d_rocket_engine_libsql_wasm`](../d_rocket_engine_libsql_wasm/README.md)
ship, the migration for those is the
same: add the engine package, call its
`register()`, swap the import. The
`DbEngine` / `EngineRegistry` /
`AsyncQueryProvider` contract is
identical across engines; only the engine
package changes.

## What did NOT change in 2.0

For the record, the following 1.x APIs
are unchanged in 2.0:

* `@Serializable` / `@SerializableField` /
  `fromJson` / `toJson`
* `@RestClient` / `RestClient.call<T>` /
  interceptors / wrap-around clients /
  cancelable requests
* `IQueryable<T>` / `IEnumerable<T>` /
  `Expr` / `EnumerableQuery` /
  in-memory LINQ operators
* `@Table` / `@Column` / `@ForeignKey` /
  `@Index` / `@Embedded`
* `EntityMeta` / `ChangeTracker` /
  `MigrationBase` / `AutoMigrator`
* `SyncProvider` / `SyncQueue` /
  `ConflictResolver` /
  `MergeStrategies`
* `WebSocketClient` / `SseClient`

See
[CHANGELOG.md](../CHANGELOG.md) for the
full list of changes in 2.0.0.
