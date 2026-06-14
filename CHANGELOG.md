# Changelog

All notable changes to `d_rocket` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] — 2026-06-13

Patch release. Fixes the README's doc-link index
on the **published package** (the pub.dev tarball
includes the README, so the 1.0.1 fix only landed
on GitHub). The 1.0.2 tarball carries the same
README fix as GitHub commit `c716699`.

* **14 doc links in README** pointed to
  `blob/main/doc/0X-...` at the repo root, but
  the docs actually live under
  `packages/d_rocket/doc/0X-...` (the repo is a
  monorepo with the d_rocket package under
  `packages/`). All 14 now have the correct
  `packages/d_rocket/` prefix.
* **2 stale names** in the "Docs" section survived
  the v1.0.0 rename: `@RocketTable` → `@Table`
  in the Layer 4 bullet, and the CLI tools
  `d_rocket:rocket_migration` / `d_rocket:rocket_closure`
  → `d_rocket:migration` / `d_rocket:closure`.

The 17 remaining `@Rocket*` / `d_rocket:rocket_*`
references in the README are the rename-mapping
table (lines 79-86) and the CHANGELOG entries —
intentional historical record.

## [1.0.1] — 2026-06-13

Patch release. No API changes. Fixes the
pub.dev scoring report and the doc link index.

* **Moved `lib/example/bookstore.dart` and
  `lib/example/quickstart.dart` to `example/`.**
  Both files require the codegen output to compile
  (they import `d_rocket_registry.g.dart` and
  `bookstore.g.dart`), which made pana fail the
  static-analysis check on the published tarball
  (5 errors, all `URI_HAS_NOT_BEEN_GENERATED` /
  `UNDEFINED_FUNCTION`). Files in `example/` are
  not analyzed by pana, so the score recovers.
  The codegen-emitted central registry
  (`lib/d_rocket_registry.g.dart`) was patched
  to import the example from its new location.
  The two test files that imported the example
  via `package:d_rocket/example/bookstore.dart`
  were updated to use a relative import.
* **README doc-index fixes.** The 14 links in
  the doc index pointed to `/docs/` (with 's');
  the actual folder is `/doc/`. The 3 inline
  doc references pointed to short file names
  (`serialization.md`, `rest.md`, `linq.md`)
  that no longer exist (renamed to
  `04-layer-1-serialization.md`,
  `05-layer-2-rest.md`, `06-layer-3-linq.md` in
  the v0.4 doc reorganization). Also two stale
  identifiers in the overview table and the top
  code sample (`RocketDbContext` → `DbContext`,
  `RocketDb.open` → `Db.open`).
* **CHANGELOG header cleanup.** Removed the
  "— First stable release" subtitle from the
  1.0.0 header to match the version-only
  convention used elsewhere.

## [1.0.0] — 2026-06-12

The first stable, production-ready release of `d_rocket`. The
public API is now frozen within the `1.x` series: minor
versions may add features, patch versions fix bugs, and
breaking changes will trigger a `2.0` bump.

This release consolidates four prior pre-releases (`0.1.0-dev`, `0.3.0-dev`,
`0.4.0-dev`, `0.5.0-dev`) into a single, cohesive
1.0. The SQLite storage engine is now bundled directly in
this package; the `d_rocket_provider_sqlite` companion
package is kept as a thin compatibility shim for projects
that have not yet migrated.

### Breaking changes

* **The `Rocket` prefix is gone from the public
  API.** Every public type and every CLI command
  has been renamed. The old `RocketTable` is now
  `Table`; `RocketDbContext` is `DbContext`; the
  CLI command `d_rocket:rocket_migration` is now
  `d_rocket:migration`; etc. The full mapping is
  in the README's "Breaking changes in v1.0 — the
  rename" section. The annotation `@RocketMigration`
  is now `@Migration`; the abstract base class that
  the codegen-emitted migration subclass extends
  is `MigrationBase` (the two names are deliberately
  distinct to avoid a same-library collision with
  the annotation). Codegen output is regenerated
  from scratch on every build, so users that ran
  `build_runner` on the pre-release will need a
  one-time `dart run build_runner build
  --delete-conflicting-outputs` after upgrading.

### Highlights

- **One package, one mental model, one generator.** Annotation-
  driven serialization, REST, LINQ, and ORM share the same
  design vocabulary, error model, and `initializeD()` wiring.
- **Async-first throughout.** Every terminal query operator
  has an `*Async_` sibling that returns a `Future`. No
  callback chains.
- **SQLite-bundled.** `RocketDb.open(path: ...)` returns a
  fully-wired database. `package:sqlite3` is the only
  engine shipped out of the box.
- **Offline-first sync & realtime.** `SyncProvider` for
  push/pull pipelines, `WebSocketClient` and
  `ServerSentEventsClient` for typed realtime streams.
- **989 tests across the runtime, the codegen, and the
  SQLite engine** — all passing.

### Added (since 0.4.0-dev)

#### Layer 1 — Serialization

- `@Serializable` with `fromJson` / `toJson` codegen.
- `JsonNaming` policy: `none`, `snakeCase`, `camelCase`,
  `kebabCase`, `pascalCase`.
- `UnknownKeyPolicy`: `ignore` (default, drop unknown keys),
  `strict` (throw), `capture` (route extras to an
  `extra: Map<String, Object?>` field — the class must
  declare one).
- `@JsonKey(name: ..., ignore: ..., requiredKey: ...,
  defaultValue: ..., converter: ..., useEnumIndex: ...,
  unknownEnumValue: ...)` for per-field overrides.
- `Format` (class, not enum): `Format.trim()`,
  `Format.uppercase()`, `Format.lowercase()`,
  `Format.date('yyyy-MM-dd' | 'iso8601')`,
  `Format.custom(name)`, `Format.customWith(type)`.
- `@SerializableUnion` for sealed sum types with
  discriminator dispatch.

#### Layer 2 — REST

- `@RestClient` with `@HttpGet` / `@HttpPost` / `@HttpPut` /
  `@HttpPatch` / `@HttpDelete` / `@HttpHead`.
- Parameter binding: `@Path`, `@Query`, `@Header`, `@Body`,
  `@Field`, `@Part`, `@RawBody`.
- `RestConfig` for one-place resilience configuration.
- `RetryPolicy` with `Backoff.exponential` / `Backoff.fixed`
  / `Backoff.linear`.
- `RateLimit(requestsPerSecond: ...)` token-bucket throttle.
- `CircuitBreaker` state machine (`closed` → `open` →
  `halfOpen` → `closed`) with `dRest.circuitState<T>()`.
- `RestInterceptor` interface and `dRest.use(...)` chain
  (auth, logging, tracing, metrics).
- Typed exception hierarchy: `RestHttpException`,
  `NetworkException`, `RestConfigException`.
- `CancelToken` for cancellable requests.
- `Stream<T>` return types for streaming endpoints.

#### Layer 3 — LINQ

- `IQueryable<T>` with deferred execution.
- Operators: `where_`, `ofType_`, `select_`, `take_`, `skip_`,
  `takeWhile_`, `skipWhile_`, `orderBy_`, `orderByDescending_`,
  `thenBy_`, `thenByDescending_`, `distinct_`, `concat_`,
  `union_`, `intersect_`, `except_`, `any_`, `all_`,
  `contains_`, `count_`, `longCount_`, `sum_`, `average_`,
  `min_`, `max_`, `aggregate_`, `first_`, `firstOrDefault_`,
  `single_`, `singleOrDefault_`, `elementAt_`,
  `elementAtOrDefault_`, `toList_`, `toSet_`, `toMap_`,
  `asEnumerable_`, `cast_`, `join_`, `groupJoin_`, `groupBy_`.
- Async terminal operators: `toListAsync_`, `toSetAsync_`,
  `firstAsync_`, `firstOrDefaultAsync_`, `countAsync_`,
  `sumAsync_`, `averageAsync_`, `minAsync_`, `maxAsync_`,
  `anyAsync_`, `allAsync_`.
- `Expr` DSL for expression-tree portability (the same
  `where_(...)` predicate is evaluated in-memory by the
  LINQ provider or pushed down to SQL by the ORM).
- Closure-sugar extensions for prototyping over
  `Iterable<T>`.
- Reactive `watch()` returning a `Stream` for live data.

#### Layer 4 — ORM (SQLite-bundled)

- `@RocketTable('table_name')` for entity declaration.
- `@PrimaryKey(autoIncrement: true)`, `@Column(name: ...,
  nullable: true, unique: true)`.
- Type mapping: `int`, `double`, `String`, `bool`,
  `DateTime` (ISO-8601), `Uint8List` (BLOB).
- `@BelongsTo` and `@HasMany` for navigation properties.
- `RocketDb.open(path: ..., strategy: ...)` /
  `RocketDb.inMemory()`.
- Change-tracked `DbSet<T>`: `add` / `addAsync`,
  `updateWhere` / `updateWhereAsync`, `removeWhere` /
  `removeWhereAsync`.
- `saveChanges()` / `saveChangesAsync()` flushes the change
  set in a single transaction.
- `include_<T>()` codegen for eager-loading related
  entities in one round-trip.
- `asLinqQueryable()` bridge to the SQL LINQ provider.
- Bulk operations: `addAll`, `updateAll`, `removeAll`.
- Reactive queries: `watch()` returns a `Stream`.

#### Migrations

- `Migration` base class with `id`, `version`, `name`,
  `up(exec)`, `down(exec)`.
- `MigrationRunner` for direct execution.
- `MigrationStrategy` with declarative `migrations` list
  AND imperative `onCreate` / `onUpgrade` / `onDowngrade`
  callbacks.
- Automatic upgrade / downgrade detection based on
  `currentVersion()` vs. `targetVersion`.
- `_d_rocket_migrations` table for persisted migration
  history.
- `dart run d_rocket:rocket_migration add <name>` CLI
  scaffolder.
- `dart run d_rocket:rocket_migration doctor` validator.

#### Sync (offline-first)

- `SyncProvider` interface for push / pull pipelines.
- `SyncOp` queue with persistence to SQLite.
- Background flush on table-change watch streams.
- Conflict-resolution policies: `lastWriterWins` (default)
  + `serverWins` + `clientWins` + custom callback.
- Identity persistence for re-attach after process restart.
- Exponential-backoff retry on `NetworkException`.

#### Realtime

- `@WebSocketRoute` for typed WebSocket methods returning
  `Stream<T>`.
- `@SseRoute` for typed Server-Sent Events methods
  returning `Stream<T>`.
- Reconnect with exponential backoff.
- Heartbeat / ping support.

#### Codegen (`d_rocket_builder`)

- `d_rocket:rocket_serializer` builder — emits per-class
  `fromJson` / `toJson` and central `register<X>Serializer`.
- `d_rocket:rocket_rest_client` builder — emits per-interface
  `RestClient` implementations with interceptors, retry, and
  serialization wired in.
- `d_rocket:rocket_table` builder — emits per-class
  `fromRow` and `setId` closures for the ORM.
- Single generated `d_rocket_registry.g.dart` with
  `initializeD()` that registers every annotated class in
  the project.

### Migration from `d_serializer` / `d_rest` 0.x

- `d_serializer` 1.3.0 was absorbed into `d_rocket 1.0`.
  Replace `package:d_serializer/d_serializer.dart` with
  `package:d_rocket/d_rocket.dart`. The annotation API is
  unchanged; the only API renames are `Serializer.fromJson`
  → `Serializer.fromJson<T>` and `Format` import path.
- `d_rest` 0.1.0 was absorbed into `d_rocket 1.0`. Replace
  `package:d_rest/d_rest.dart` with
  `package:d_rocket/d_rocket.dart`. The `@RestClient`
  API is unchanged; resilience config moved from
  `RestClientBuilder` to `RestConfig` and the
  `circuitState<T>()` extension moved to `dRest.circuitState<T>()`.

### Acknowledgements

The API design draws on patterns from several well-known
frameworks: Entity Framework Core (DbContext, change
tracking, Migrations), .NET LINQ (deferred execution,
operator matrix), Retrofit (annotated interfaces), Moshi
and kotlinx.serialization (annotation-driven serialization),
and sqflite (SQLite migration runner).

### License

© Torogoz Tech. Released under the MIT License.
