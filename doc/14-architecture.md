# Architecture

The internal design of `d_rocket`. This document is
for contributors and for advanced users who want to
extend the framework.

---

## Layered design

```
                  ┌─────────────────────────────────────┐
                  │                                     │
                  │         application code            │
                  │   (your @Serializable, @RestClient, │
                  │    @Table, etc.)              │
                  │                                     │
                  └─────────────────┬───────────────────┘
                                    │
                                    ▼
                  ┌─────────────────────────────────────┐
                  │                                     │
                  │       d_rocket_builder              │
                  │   (codegen, build_runner)           │
                  │                                     │
                  │   - reads annotations               │
                  │   - emits *.g.dart files            │
                  │   - emits d_rocket_registry.g.dart  │
                  │                                     │
                  └─────────────────┬───────────────────┘
                                    │
                                    ▼
                  ┌─────────────────────────────────────┐
                  │                                     │
                  │      d_rocket CORE (2.0.0)          │
                  │      engine-agnostic                 │
                  │                                     │
                  │  ┌─────────────┐  ┌─────────────┐  │
                  │  │ serializer  │  │ rest        │  │
                  │  └─────────────┘  └─────────────┘  │
                  │  ┌─────────────┐  ┌─────────────┐  │
                  │  │ linq        │  │ orm         │  │
                  │  │ (35 ops)    │  │ (DbContext) │  │
                  │  └─────────────┘  └─────────────┘  │
                  │  ┌─────────────┐  ┌─────────────┐  │
                  │  │ sync        │  │ realtime    │  │
                  │  └─────────────┘  └─────────────┘  │
                  │  ┌──────────────────────────────┐  │
                  │  │ DbEngine contract (3 methods)│  │
                  │  │ SqlDialect   (3 methods)     │  │
                  │  │ EngineRegistry               │  │
                  │  └──────────────────────────────┘  │
                  │                                     │
                  └─────────────────┬───────────────────┘
                                    │
                ┌───────────────────┼───────────────────┐
                │                   │                   │
                ▼                   ▼                   ▼
      ┌──────────────────┐ ┌──────────────────┐ ┌──────────────────┐
      │ d_rocket_engine_ │ │ d_rocket_engine_ │ │ d_rocket_engine_ │
      │ sqlite (2.0.0)   │ │ postgres (2.0.0) │ │ web (2.0.0)      │
      │                  │ │                  │ │                  │
      │ - SqliteEngine   │ │ - PostgresEngine │ │ - WebEngine      │
      │ - Db facade      │ │ - PgDb facade    │ │ - WebDb facade   │
      │ - SQLiteProvider │ │ - PgProvider     │ │ - WebProvider    │
      │ - SQLiteDialect  │ │ - PostgresDialect│ │ - WebDialect     │
      │                  │ │ - listen/notify  │ │ (IndexedDB via   │
      │                  │ │                  │ │  idb_shim)       │
      │ package:sqlite3  │ │ package:postgres │ │ package:idb_shim │
      │ (sqlcipher opt)  │ │ (wire protocol)  │ │ (browser)        │
      └──────────────────┘ └──────────────────┘ └──────────────────┘
```

The runtime is split into two tiers in 2.0.0:

* **Core** (`d_rocket`) — engine-agnostic. Contains all
  six layers, the `DbEngine` contract, the `SqlDialect`
  contract, the `EngineRegistry`, and the
  `AsyncQueryProvider` interface. No DB driver dependency.
* **Engines** (one package per engine) — implements
  `DbEngine`. Each engine is a thin wrapper around a
  Dart DB driver (`package:sqlite3`, `package:postgres`,
  `package:idb_shim`).

The same `DbContext`, `DbSet<T>`, `@Table`, and LINQ
code runs on every engine. Switching engines is a
1-line change in `main.dart` (the
`dRocketSqlite()` / `dRocketPostgres()` /
`dRocketWeb()` registration call).

The codegen is a separate `build_runner` integration.
The platform plugins are well-known Dart packages —
`d_rocket` is a user, not a re-implementer, of these
primitives.

### 2.0.0 — the engine contract

The boundary between core and engines is a small set
of interfaces. The `DbEngine` contract is what an
engine package implements. The `AsyncQueryProvider`
interface is what the engine returns to d_rocket
core. The `SqlDialect` is the LINQ-to-SQL translator
hook (the in-memory `Expr` tree gets walked by the
dialect to produce a `SqlFragment`).

```dart
abstract class DbEngine {
  String get name;            // e.g. "sqlite", "postgres", "web"
  bool get isAvailable;       // platform probe (libsqlite3 loaded?)
  Future<AsyncQueryProvider> open({
    String? path,
    String? password,
    Object? encryptionConfig, // engine-specific shape
  });
}

abstract class AsyncQueryProvider {
  bool get isOpen;
  Future<void> executeAsync(String sql, [List<Object?>? binds]);
  Future<List<Object?>> selectAsync(String sql, [List<Object?>? binds]);
  Future<int> lastInsertRowIdAsync();
  Future<void> beginTransactionAsync();
  Future<void> commitAsync();
  Future<void> rollbackAsync();
  Future<void> disposeAsync();
}
```

The default `SqlDialect` is
SQLite-flavoured (`DefaultDialect`). The Postgres
engine ships `PostgresDialect` which overrides the
`?`-placeholder rewrite (Postgres uses `$1, $2, ...`
and the provider rewrites on emit). Adding a new
engine (e.g. MySQL for 2.2.0) means implementing
`DbEngine` + `AsyncQueryProvider` + `SqlDialect`.

## The six layers, internally

Each layer in `d_rocket` is a focused module with a
clean contract to the others. Cross-layer dependencies
flow downward (LINQ uses Serializer; ORM uses LINQ;
Sync uses ORM; Realtime uses Serializer).

### `lib/src/serializer/`

The serializer layer has three parts:

- **`@Serializable` / `@SerializableUnion`** — the
  annotation surface.
- **`Serializer`** — the central registry.
- **`Format<T>`** — the encoder/decoder contract.

The registry is a singleton (one per process). On
`initializeD()`, every annotated class is registered
with a `fromJson` and `toJson` function. Other
layers (`rest`, `realtime`) call
`Serializer.fromJson<T>(raw)` to decode payloads.

### `lib/src/rest/`

The REST layer has four parts:

- **`@RestClient`** — the annotation surface.
- **`RestConfig`** — resilience (retry, circuit
  breaker, rate limit, response cache).
- **`RestInterceptor`** — the cross-cutting concern
  chain.
- **`dRest.create<T>()`** — the factory that
  instantiates the codegen-emitted implementation.

The codegen reads a `@RestClient` interface and emits
a private `_RestClient` class that implements it. The
factory wraps that implementation with the configured
interceptors and resilience policies. The user's
code never sees the implementation directly.

### `lib/src/linq/`

The LINQ layer has two parts:

- **`Queryable<T>`** — the deferred-execution
  queryable.
- **`Expr<T, R>`** — the expression tree.

`Queryable<T>` is the user-facing API. `Expr<T, R>` is
the internal AST that the providers consume. The
`where_`, `orderBy_`, `take_`, etc. operators accept
`Expr<T, R>` and return a new `Queryable<T>`. A
terminal (`toList_`, `firstOrDefault_`, etc.) is when
the provider is invoked.

There are two providers:

- **`LinqInMemoryProvider`** — evaluates the `Expr`
  tree against an in-memory `Iterable<T>`.
- **`LinqSqlProvider`** — translates the `Expr` tree
  to SQL and runs it against a `DbSet<T>`.

The framework dispatches to the right provider based
on the source type. Adding a new provider (e.g. for
a remote API) is a matter of writing one
`LinqProvider<T>` implementation.

### `lib/src/sqlite/` and `lib/src/orm/`

The SQLite engine and the ORM are split into two
modules. The engine is the LINQ-to-SQL translator
plus the `sqlite3` wrapper; the ORM is the
`@Table` annotation surface, the `Db`
facade, the `DbSet<T>` change-tracked set, and the
migration runner.

The engine knows about `DbSet<T>` (Layer 4 source) and
translates LINQ queries to SQL. The ORM knows about
`@Table` and exposes the typed API. The boundary
is the `AsyncQueryProvider` contract — the engine
implements it, the ORM consumes it.

### `lib/src/sync/`

The sync layer is built on top of the ORM. The
`SyncProvider` interface is the contract your backend
integration implements; the runtime is the
push / pull coordinator, the conflict resolver, and
the offline queue.

The queue is stored in the local SQLite database as a
table; the change tracker emits `SyncOp`s on every
`saveChanges()`.

### `lib/src/realtime/`

The realtime layer reuses the REST layer's
interceptors and the serializer layer's codecs. It's
a thin wrapper around the platform's WebSocket and
SSE primitives.

## The `Expr` AST

The expression tree is the canonical query language.
It's a tree of `Expr<T, R>` nodes, where `T` is the
input type and `R` is the output type.

```
Expr<T, R> (abstract)
├── ExprParam<T>          // a parameter reference, e.g. 'p'
├── ExprConst<R>          // a constant value
├── ExprMember<T, M>      // field access, e.g. p.name
├── ExprBinary<L, R>      // binary op, e.g. p.x == v
├── ExprUnary<X>          // unary op, e.g. !p.done
├── ExprCall<T, R>        // method call, e.g. p.startsWith('a')
├── ExprConditional<T>    // ternary, e.g. cond ? a : b
├── ExprLambda<T, R>      // lambda, e.g. p => p.x
└── ExprAnon<R>           // anonymous object, e.g. { 'id': ... }
```

The codegen reads the source AST (via the `analyzer`
package), normalizes it, and emits the
`Expr.lambda(...)` form. The closure-sugar builder
(`d_rocket_builder:closure`) is a wrapper that
makes the closure form (`p => p.x == v`) work at the
source level; the codegen then unwraps it back to the
explicit form for portability.

The SQL provider traverses the tree and emits SQL.
The in-memory provider evaluates the tree against an
`Iterable<T>`. Both providers share the same
visitor pattern, so adding a new node type is a
matter of adding a visitor method.

## The `ChangeTracker`

The ORM's `ChangeTracker<T>` is the bridge between
your `add` / `updateWhere` / `removeWhere` calls and
the actual SQL. It maintains three lists:

- **`Added`** — entities that should be inserted.
- **`Modified`** — entities that should be updated.
- **`Deleted`** — entities that should be deleted.

`saveChanges()` opens a transaction, walks the
tracker, and emits the SQL:

```
tracker.added    → INSERT
tracker.modified → UPDATE
tracker.deleted  → DELETE
```

The codegen emits a `setId(entity, id)` closure for
each `@Table` class. After an INSERT, the
runtime calls `setId` with the DB-assigned id so the
in-memory entity is up-to-date.

For a `Modified` entry, the runtime diffs the entity
against the original (pre-modification) snapshot. The
diff is at the field level, so only the changed
columns are updated.

## The codegen pipeline

`d_rocket_builder` is a `build_runner` integration.
It registers seven `Builder`s (the `build.yaml` is the
authoritative source):

| Builder id | What it reads | What it emits |
|---|---|---|
| `d_rocket_builder:record` | `extends Record` | per-class `_$<Name>Init` + `register<X>Record` |
| `d_rocket_builder:serializer` | `@Serializable`, `@SerializableUnion` | per-class `fromJson` / `toJson`, central `register<X>Serializer` calls |
| `d_rocket_builder:rest_client` | `@RestClient` | per-interface implementation with interceptors, retry, serialization |
| `d_rocket_builder:rocket_table` | `@Table`, `@PrimaryKey`, `@Column`, `@ForeignKey`, `@Index`, `@Embedded` | per-class `EntityMeta` (table name, columns, indexes, PK, FKs, embeds) |
| `d_rocket_builder:rocket_migration` | `@Migration` | per-class `_$<Name> extends MigrationBase` |
| `d_rocket_builder:realtime` | `@WebSocketClient`, `@SseClient` | per-interface typed `Stream<T>` client |
| `d_rocket_builder:record_registry` | the union of all the above | a single `d_rocket_registry.g.dart` with the central `initializeD()` |

The seven builders run in parallel. Their outputs are
collected by the central `d_rocket_registry.g.dart`
generator, which imports every `*.d_rocket_*.g.dart`
and exposes a single `initializeD()` function. The dev
calls `initializeD()` once at app startup; no other
wiring is needed.

> **Note (historical):** in 1.x the builders were
> namespaced `d_rocket:*` and the table builder was
> `d_rocket:table`. Both are kept as 1.x typedefs for
> source compatibility but the canonical 2.0.0 ids
> are `d_rocket_builder:*` and `d_rocket_builder:rocket_table`.

The output is deterministic — re-running the
generator on unchanged source produces byte-identical
`*.g.dart` files. This is important for CI: a diff
in the generated output means something changed.

The closure-sugar translation is **not** a builder
— it's the CLI `d_rocket:closure` (exposed as the
`closure` executable in `d_rocket/bin/closure.dart`).
It walks the source and rewrites `Iterable.where((x) => ...)`
into `Expr.lambda(...)` calls. Run it via
`dart run d_rocket:closure transform-file path/to/file.dart`.

## Extension points

The framework is open. You can add your own:

### Custom `Format<T>`

```dart
class MyFormat<T> implements Format<T> {
  const MyFormat();

  @override
  Object? toJson(T value) { /* ... */ }

  @override
  T fromJson(Object? raw) { /* ... */ }
}

@JsonKey(format: MyFormat())
final MyType field;
```

### Custom `RestInterceptor`

```dart
class MyInterceptor implements RestInterceptor {
  @override
  Future<RestRequest> onRequest(RestRequest request) async {
    // mutate the request, or throw RestException to abort
    return request;
  }
  @override
  Future<RestResponse<dynamic>> onResponse(
    RestResponse<dynamic> response,
  ) async => response;
  @override
  Future<void> onError(
    RestRequest request,
    Object error,
    StackTrace st,
  ) async { /* log / rethrow */ }
}

dRest.useDefaults(interceptors: [MyInterceptor()]);
```

### Custom `ConflictPolicy`

```dart
class MyPolicy extends ConflictPolicy {
  const MyPolicy();
  @override
  Map<String, Object?> resolve(
    Map<String, Object?> local,
    Map<String, Object?> server,
  ) {
    // return the field-level merge you want
    return {...server, ...local};
  }
}

// then on the SyncProvider:
MyBackendSyncProvider(policy: const MyPolicy());
```

### Custom `AsyncQueryProvider`

```dart
class MyDbProvider implements AsyncQueryProvider {
  @override
  bool get isOpen => /* ... */;
  @override
  Future<void> executeAsync(String sql, [List<Object?>? binds]) async { /* ... */ }
  @override
  Future<List<Object?>> selectAsync(String sql, [List<Object?>? binds]) async { /* ... */ }
  @override
  Future<int> lastInsertRowIdAsync() async => 0;
  @override
  Future<void> beginTransactionAsync() async { /* ... */ }
  @override
  Future<void> commitAsync() async { /* ... */ }
  @override
  Future<void> rollbackAsync() async { /* ... */ }
  @override
  Future<void> disposeAsync() async { /* ... */ }
}
```

A custom `AsyncQueryProvider` is the way to wire a
new engine. Wrap it in a `DbEngine` and pass it to
`Db.open(engine: ...)`, or register it with
`EngineRegistry.register(myEngine)` and use the
`dRocketSqlite()` / `dRocketPostgres()` / `dRocketWeb()`
helpers to register the shipped engines.

## Threading model

`d_rocket` is single-threaded per isolate. The
runtime, the codegen output, and the user's code all
run on the same event loop.

For multi-threaded work (e.g. a long-running sync),
use `Isolate.spawn` directly with `package:d_rocket`
on the worker isolate — there is no special
`IsolateWorker<Db>` helper in 2.0.0. Each isolate
has its own `Db` instance and its own event loop;
messages are passed via `SendPort` / `ReceivePort`.
The framework's API is the same on every isolate:
the same `@Table` classes, the same `DbSet<T>`
chains, the same `saveChanges()`.

## Build-time vs runtime

The split is:

- **Build-time** (the codegen): reads the source
  AST, emits the `*.g.dart` files. Runs once per
  source change.
- **Runtime** (`d_rocket`): the registry, the LINQ
  provider, the ORM, the sync runtime, the realtime
  client. Runs in the user's app.

The codegen output is committed to the repo
(by convention) so a fresh checkout can build
without running the codegen. The CI verifies the
generated files are up-to-date with
`build_runner build --delete-conflicting-outputs`.

## Performance notes

- **Codegen is incremental** — only the files that
  changed (or that depend on a changed annotation)
  are re-emitted. `build_runner` handles this.
- **Runtime dispatch is fast** — the `Expr` tree is
  visited once per terminal; there is no
  interpretation per operator.
- **Change tracking is per-row** — the diff is at
  the field level, so updates are minimal.
- **The LINQ provider is lazy** — the chain is
  composed without running. The terminal is the only
  point where the SQL is emitted.
- **WebSocket / SSE have a per-message overhead** —
  the framework batches messages per frame where
  possible.
- **Interceptors are zero-cost when not registered**
  — the chain is a no-op if no interceptors are
  added.

## Future directions

The framework is at 2.0.0. Future directions include:

- **`d_rocket_admin`** — a Flutter web admin UI
  on top of the engine.
- **Dart macros** for codegen (replaces the
  `build_runner` integration; requires analyzer
  `^13.0.0`).
- **Form binding** — a `@RocketForm` annotation
  for two-way binding of `@Table` entities to form
  widgets.
- **Cross-engine benchmarks** — quantify the
  per-engine LINQ-to-SQL overhead vs EF Core /
  Hibernate.

These are not commitments; they are areas where
contributions are welcome.

## Contributing to `d_rocket`

Open an issue first to discuss the design. For
bugfixes, a PR with a test is the standard
contribution. The framework has 989 tests; new
features should be accompanied by tests that cover
the happy path and the obvious edge cases.

The CI runs:

- `dart pub get`
- `dart analyze`
- `dart test`
- `dart run build_runner build --delete-conflicting-outputs`
- `dart pub publish --dry-run` (to verify the package
  layout is publishable)

A green CI is required for a merge.
