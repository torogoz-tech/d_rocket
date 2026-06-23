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

---

## What's NEW in 2.0 (not in 1.x)

### `d_rocket_lints` is a separate package

In 1.x, the IDE lints
(`d_rocket_untranslated_closure_linq`,
`d_rocket_n_plus_one`) shipped inside
`d_rocket_builder`. In 2.0.0 they ship as
a dedicated dev-dependency:

```yaml
# pubspec.yaml — 2.0+
dev_dependencies:
  d_rocket_lints: ^2.0.0
```

Then enable in `analysis_options.yaml`:

```yaml
analyzer:
  plugins:
    - custom_lint
```

`d_rocket_builder` re-exports the lints so
existing consumers don't break; new projects
should depend on `d_rocket_lints` directly.

### `d_rocket:migration check` (CI-friendly schema diff)

The `check` subcommand computes the pending
schema diff between your codegen-supplied
entity metas and the actual SQLite schema.
It exits 1 if any unsafe diffs (e.g.
`DROP TABLE`), which is the signal you want
in CI to gate merges:

```bash
$ dart run d_rocket:migration check \
    --db app.db \
    --entities lib/db/entities.dart
```

The entities file is a small Dart file you
write that exports a top-level
`List<EntityMeta> entityMetas`. See
[doc/11-cli.md](./11-cli.md) for the full
reference.

### Postgres engine ships as `d_rocket_engine_postgres`

The Postgres engine is a separate package
in 2.0.0. Add it as a regular dependency
and call `dRocketPostgres()` at startup:

```yaml
dependencies:
  d_rocket: ^2.0.0
  d_rocket_engine_postgres: ^2.0.0
```

```dart
dRocketPostgres();
final db = await PgDb.open(url: 'postgres://...');
```

`PgDb` mirrors the SQLite `Db` facade for
the Postgres engine; the
`db.set<T>().where(…).toListAsync_()`
flow works the same way (Postgres dialect
uses `STRPOS` + `jsonb_build_object`).

### Web engine ships as `d_rocket_engine_web`

For browser apps, IndexedDB-backed
storage:

```yaml
dependencies:
  d_rocket: ^2.0.0
  d_rocket_engine_web: ^2.0.0
```

```dart
dRocketWeb();
final db = await WebDb.open(
  config: WebEngineConfig(databaseName: 'my_app'),
);
```

Known 2.0 limitations (deferred to 2.1):
cursor push-down on `idb_shim` 2.9.2 hangs;
the runtime falls back to in-memory
materialization for those paths (the
fallback is correct, just slower).

---

## 11. New LINQ operators (Phase 1a)

Five LINQ operators that were missing in 1.x or only
existed as sync terminals in 1.x:

| Operator | Status in 1.x | Status in 2.0.0 |
|---|---|---|
| `reverse_()` | SQLite-specific (`ORDER BY rowid DESC`) | Portable (flips existing `ORDER BY`) — **requires a preceding `orderBy_()`** |
| `defaultIfEmpty_(T)` | Not available | New — in-memory wrapper |
| `toLookup_<K>(...)` | Sync only | Sync + `toLookupAsync_<K>(...)` |
| `zip_<T2>(...)` | Sync only | Sync + `zipAsync_<T2, R>(...)` |
| `sequenceEqual_<T2>(...)` | Not available | New — sync + `sequenceEqualAsync_<T2>(...)` |

### 11.1 `reverse_()` — the breaking change

**Before (1.x):**

```dart
// Worked because the 1.x implementation
// emitted ORDER BY rowid DESC (SQLite-specific).
final result = await db.orders
    .asQueryable()
    .reverse_()
    .toListAsync_();
```

**After (2.0.0):**

```dart
// 2.0.0 requires a preceding orderBy_():
// the SQL translator flips the ASC/DESC on
// each key, not a hardcoded "rowid DESC".
final result = await db.orders
    .asQueryable()
    .orderBy_(o => o.id)   // ← required in 2.0.0
    .reverse_()
    .toListAsync_();
```

If you skip the `orderBy_()`, the translator throws
`StateError` at `toListAsync_()` time. The error
message tells you exactly what to do.

### 11.2 `defaultIfEmpty_()` — new in 2.0.0

```dart
// "All my filters, or a default filter if I have none".
final filters = await db.userFilters
    .asQueryable()
    .where_(f => f.userId == userId)
    .defaultIfEmpty_(defaultFilter)
    .toListAsync_();
```

The operator is a `Queryable<T>` subclass that delegates
the SQL emission to the source and applies the
default-if-empty logic in `toListAsync_` (and via the
iterator for the sync path).

### 11.3 Async variants of `toLookup_`, `zip_`, `sequenceEqual_`

The 1.x `toLookup_<K>(...)`, `zip_<T2>(...)` were
sync terminals — for async sources you had to call
`toList_()` first. 2.0.0 adds async variants:

```dart
// 1.x:
final lookup = buildLookup(
  await q.toListAsync_(), keySelector,
);

// 2.0.0:
final lookup = await q.toLookupAsync_<K>(
  keySelector: keySelector,
);

// Same pattern for zip_ and sequenceEqual_:
final pairs = await q1.zipAsync_<T2, R>(q2, combiner);
final equal = await q1.sequenceEqualAsync_<T2>(q2);
```

The `*Async_` variants are the recommended path for
any queryable that runs SQL.


