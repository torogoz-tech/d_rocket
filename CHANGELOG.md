# Changelog

All notable changes to `d_rocket` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] — 2026-06-15

Minor release. Adds the auto-migration system
(opt-in): the framework detects diffs between
the schema declared by the codegen-emitted
entity list and the last applied schema on
disk, applies the safe changes in a single
transaction, and reports the unsafe changes
for the user to handle manually.

* **New `autoMigrate` flag on `Db.open` and
  `Db.inMemory`.** When set, `Db.open` (and
  `Db.inMemory`) run the auto-migrator after
  any hand-written `MigrationStrategy`. The
  flag is opt-in: existing callers that do
  not pass `entityMetas:` see no change in
  behaviour (no `d_rocket_schema_state`
  table is created, no auto-migration runs).
  The migration system still applies
  hand-written `MigrationBase`s first, so
  projects that mix hand-written and
  auto-migrations can do so without conflict.

* **Safe operations applied automatically.**
  CREATE TABLE, CREATE INDEX, and ADD COLUMN
  (nullable or with a default literal) are
  safe and are applied in a single
  transaction. The new schema snapshot is
  written in the same transaction, so the
  snapshot is never ahead of the actual
  schema.

* **Unsafe operations reported, never
  applied.** DROP TABLE, DROP COLUMN,
  DROP INDEX, MODIFY COLUMN (type /
  nullability / default / FK change), and
  the rename heuristic are unsafe. They are
  returned in `Db.pendingSchemaDiff()` and
  in the `AutoMigrationResult.unsafe` list
  from `Db.runAutoMigrations()`. The user
  is expected to handle them explicitly
  (typically by writing a hand-rolled
  migration that performs the unsafe
  change). The auto-migrator never destroys
  data silently.

* **New public API.** `Db.runAutoMigrations()`
  drives the auto-migration on demand
  (returns the `AutoMigrationResult` with
  the safe diffs that were applied, the
  unsafe diffs that were reported, and the
  new `SchemaSnapshot`). `Db.pendingSchemaDiff()`
  returns the pending diff without applying
  anything (useful for logging, dry-runs,
  and CI checks). The `SchemaSnapshot` /
  `SchemaTable` / `SchemaColumn` /
  `SchemaIndex` / `SchemaForeignKey` /
  `SchemaDiff` / `DiffSeverity` /
  `SchemaOperationType` / `AutoMigrationResult`
  types are exposed in the package barrel
  for advanced users (custom diff tooling,
  alternative orchestrators).

* **New internal table
  `d_rocket_schema_state`.** A single-row
  key-value table that stores the last
  applied `SchemaSnapshot` as JSON. The
  table is intentionally separate from the
  existing `_d_rocket_migrations` (which
  tracks hand-written `MigrationBase` runs);
  the two coexist without sharing data. The
  `CHECK (id = 1)` constraint guards against
  accidental multi-row inserts. The
  snapshot's `version` field lets a 1.1.x
  runtime detect a snapshot from a newer
  d_rocket and refuse to migrate it (so a
  downgrade does not silently corrupt the
  schema).

* **Snapshot persistence contract.** When
  the auto-migrator runs and finds unsafe
  diffs, the safe diffs are applied but the
  new snapshot is NOT written to
  `d_rocket_schema_state`. The unsafe diffs
  keep showing up in
  `Db.pendingSchemaDiff()` on every reopen
  until the user handles them (typically by
  writing a hand-rolled migration that
  performs the unsafe change explicitly,
  then re-opening). This is intentional: a
  pending unsafe diff is a louder signal
  than a pending safe change, and we want
  the user to handle the unsafe first.

* **Tests.** 27 new cases in
  `test/orm/auto_migration/`. Covers the
  snapshot round-trip, every diff type
  (safe and unsafe), the round-trip via
  `Db.open` / `Db.inMemory`, the drop
  report (not applied) path, the file-
  backed DB round-trip, the back-compat
  `autoMigrate: false` default, and the
  empty-`entityMetas` no-op. Full suite:
  855 pass + 1 skip.

* **No codegen changes.** The snapshot is
  computed at runtime from the existing
  `EntityMeta` list. The codegen did not
  need to be touched. The
  `d_rocket_builder` 1.2.0 release is a
  no-op version bump (per the lockstep
  convention established in 1.1.1).

## [1.1.1] — 2026-06-15

Patch release. Three production-readiness fixes
that close the data-loss and data-integrity risks
flagged by an external review of d_rocket for a
clinical-scenario use case.

* **Sync queue is now persisted.** Before
  1.1.1, the pending sync queue was a
  `List<SyncChange>` in memory inside
  `DbContext`. A crash between
  `saveChangesAsync()` and `syncAsync()` lost
  every queued change. Fix: a new internal
  `SyncQueueStore` backs the queue with a
  `d_rocket_sync_queue` table in the same
  database as the user data (so it picks up
  SQLCipher encryption for free when the main
  DB is encrypted). `saveChangesAsync` inserts
  the queued change inside the same
  transaction as the data write; on
  `syncAsync` success the rows are deleted in
  a transaction; a failed sync leaves the
  rows for the next call to retry. A
  `maxQueueSize` cap (default 10,000 rows)
  drops the oldest rows when the cap is
  exceeded and logs a warning. No new
  parameters on `Db.open` / `Db.inMemory` /
  `Db.saveChangesAsync` / `Db.syncAsync` —
  the persistence is fully transparent.
  Existing callers get it for free. New
  public API: `Db.pendingSyncChanges()` is
  now an async getter that hydrates from the
  persistent store on first call.

* **FK enforcement is now on by default.**
  `PRAGMA foreign_keys = ON` is emitted on
  every `Db.open()` (in `SqliteQueryProvider`
  in both the `inMemory` and `file`
  factories). SQLite ships with FK
  enforcement off for backwards
  compatibility; without the PRAGMA,
  `FOREIGN KEY (col) REFERENCES table(col)`
  clauses in `CREATE TABLE` are parsed and
  stored but never enforced at runtime.
  This was a silent data-integrity risk: a
  row could be inserted with a dangling
  reference and the constraint violation
  would only surface if a tool happened to
  re-enable FKs. The codegen has been
  emitting `REFERENCES` clauses correctly
  for `@ForeignKey` since 1.0; the bug was
  that the engine was not enforcing them by
  default. The PRAGMA is a no-op when the
  schema has no FK clauses.

* **Two existing tests updated.** The
  `relations_test.dart` and `include_test.dart`
  cases were inserting rows with dangling
  FKs (e.g. a sale with `book_id = 999` when
  no such book existed), relying on the
  broken default. The inserts are updated to
  reference real rows, with a comment
  explaining why.

* **Tests added.** 4 new cases in
  `test/sqlite/foreign_keys_enforcement_test.dart`
  (the PRAGMA is set after every open, on
  both factories, and an INSERT with a
  dangling FK raises `SqliteException` —
  the load-bearing test that would silently
  pass if the PRAGMA were missing).
  2 new cases in
  `test/sync/persistent_sync_queue_test.dart`
  (the file-backed round-trip and the
  schema shape). 6 new cases in
  `test/orm/migration_ddl_includes_indexes_test.dart`
  (in `d_rocket_builder`, the codegen side
  of the fix). Total: 12 new cases across
  the two packages. 828 + 1 skipped.

## [1.1.0] — 2026-06-15

Minor release. Expands the SQLCipher password
support landed in 1.0.5 with the four pieces the
ecosystem needs to make encryption actually
deployable: typed tunables, an async key source,
a key-rotation helper, and a redactor for
accidental log leaks.

* **`EncryptionConfig` — typed SQLCipher
  tunables.** A new `EncryptionConfig` class is
  passed via `encryptionConfig:` on `Db.open` and
  `Db.inMemory`. It wraps the four SQLCipher
  PRAGMAs a security-conscious app most commonly
  tunes: `kdfIterations` (default 256,000 →
  `PRAGMA cipher_default_kdf_iter`), `pageSize`
  (default 4096 → `PRAGMA cipher_page_size`),
  `hmacUse` (default `true` → `PRAGMA
  cipher_use_hmac`), and `memorySecurity`
  (default `true` → `PRAGMA cipher_memory_security`).
  The four PRAGMAs are applied right after
  `PRAGMA key` in the order SQLCipher requires,
  and the config is validated at construction:
  a bad `kdfIterations` or `pageSize` raises
  `ArgumentError` before the engine is touched.
  The default config matches SQLCipher 4.x
  defaults, so callers that pass the config
  without tuning any value get the same behavior
  as 1.0.5.

* **`KeyProvider` — async password source.** A
  new `KeyProvider` abstraction lets the encryption
  password come from any async store (typically
  the platform secure storage) instead of being
  passed as a literal `String`. `Db.open` and
  `Db.inMemory` accept `keyProvider:` (mutually
  exclusive with `password:`); the value is awaited
  once per open and held in memory for the lifetime
  of the connection. `d_rocket` does not cache
  across opens, so rotating the key in the keychain
  takes effect on the next `Db.open`. Two built-in
  providers ship: `StaticKeyProvider` (literal in
  memory; for tests) and `CallbackKeyProvider`
  (wraps an async function; for instrumentation
  or non-`String` sources). Consumers integrating
  with `flutter_secure_storage` (or any other
  vault) implement the `KeyProvider` interface in
  five lines on the application side, so the
  production code can declare the dependency
  without taking a Flutter-specific dep.

* **`Db.changePassword()` — key rotation.** A new
  `db.changePassword(newPassword: …)` method wraps
  `PRAGMA rekey` with the same single-quote escape
  used by the open path. The new key can also be
  supplied via `newKeyProvider: …`; the two are
  mutually exclusive. The current connection stays
  open across the rekey (the engine re-encrypts
  the page cache on the next write). The rekey
  is applied to every page, so for a multi-megabyte
  database it can take a few hundred milliseconds.
  Replaces the "call `PRAGMA rekey` through the
  provider" workaround documented in the 1.0.5
  FAQ.

* **`redactPragmaKey()` — safe SQL logging.** A
  new top-level `redactPragmaKey(String sql)`
  function replaces the literal value of any
  `PRAGMA key = '...'` or `PRAGMA rekey = '...'`
  in the input with `'***'`. Case-insensitive,
  whitespace-tolerant, and correctly handles the
  single-quote escape d_rocket uses internally.
  Useful for application-level SQL traces when
  the database is encrypted and the password
  must not appear in logs, crash reports, or
  any other observer.

* **FAQ expanded.** The "Security" section in
  `doc/13-faq.md` now also covers `KeyProvider`
  with a `flutter_secure_storage` example,
  `EncryptionConfig` with the four PRAGMAs and
  the `pageSize` migration caveat, the new
  `changePassword` flow (replacing the
  "do-it-yourself through the provider" recipe
  from 1.0.5), and `redactPragmaKey` for log
  sanitization. The threat model entry from
  1.0.5 is unchanged.

* **New tests** in
  `test/sqlite/encryption_ecosystem_test.dart`
  (29 cases): EncryptionConfig validation
  (defaults, tuned values, bad inputs, every
  documented power-of-two pageSize), built-in
  KeyProviders, mutual exclusion and empty-key
  rejection on `Db.open`, `Db.changePassword`
  argument validation, and the full
  `redactPragmaKey` redaction matrix
  (simple, escaped quote, case, whitespace,
  multi-statement, unrelated SQL, empty
  string). All tests run on the dev machine
  with no `libsqlcipher` installed.

* **Boxed `LoggingInterceptor`.** A new
  `LoggingInterceptor` in `lib/src/rest/`
  implements `RestInterceptor` and writes one
  line per request, response, and error to a
  caller-supplied sink (e.g. `print`,
  `developer.log`). The default configuration
  is conservative (method, URL, status — no
  headers, no bodies) so it is safe to drop in
  production without exposing secrets. Headers
  and bodies are opt-in via `includeHeaders: true`
  and `includeBodies: true`. When bodies are
  included, the body text is passed through
  `redactPragmaKey` by default — a SQLCipher
  database password that ends up in a request
  body is never written to the log even when
  body logging is enabled. To disable
  redaction, pass `redactBody: (s) => s`.
  Pairs naturally with the 1.0.5
  `redactPragmaKey` utility to keep REST
  tracing safe by default.

* **Typed `ConflictPolicy` hierarchy.** A new
  sealed `ConflictPolicy` class in
  `lib/src/sync/` is the preferred API over the
  bare `ConflictResolver` typedef. Four
  built-in constants are exposed: `lww`
  (alias `serverWins`, remote value wins on
  collisions — the previous default), the
  inverse `clientWins` (local value wins), and
  `custom(resolver)` for user-provided merge
  logic. The factory pairs naturally with the
  existing `MergeStrategies` helpers
  (`preferLocalColumns`, `preferRemoteColumns`,
  `maxOf`). The old `LwwConflictResolver.instance`
  and `CustomConflictResolver.wrap` shims are
  retained for back-compat and behave
  identically to the new `ConflictPolicy.lww`
  and `ConflictPolicy.custom` equivalents.

* **REST and sync docs updated.** The
  Interceptors section in
  `doc/05-layer-2-rest.md` now uses the
  real `LoggingInterceptor(log: ...)` API in
  its example (the old `LoggingInterceptor()`
  no-arg call would not compile against the
  1.1.0 signature) and documents the
  `includeHeaders` / `includeBodies` /
  `redactPragmaKey` opt-in. The conflict
  resolution section in
  `doc/08-layer-5-sync.md` adds a `ConflictPolicy`
  walkthrough alongside the existing
  `ConflictResolver` typedef.

* **New tests** in
  `test/rest/logging_interceptor_test.dart`
  (11 cases): default line shape, opt-in
  headers, opt-in bodies, `redactPragmaKey`
  default, identity-function override, custom
  redactor, and pass-through semantics for
  `onRequest` / `onResponse` / `onError`. In
  `test/sync/conflict_policy_test.dart` (16
  cases): the constant identity (lww ==
  serverWins, lww != clientWins), the merge
  semantics of `lww` and `clientWins` (with
  the empty-payload edge cases), the
  `custom(resolver)` factory (including the
  `MergeStrategies` helpers), and the
  back-compat shims.

* **Runtime observability helpers.** Four
  additive, observability-focused public
  additions that hang off the same "tell me
  the state of this DB" question:

    * `EncryptionStatus` enum in
      `lib/src/sqlite/encryption_status.dart`
      with three values: `plain` (no password
      used), `encrypted` (password used AND
      engine confirmed SQLCipher), and
      `unknown` (password used but the probe
      could not confirm the engine — most
      commonly because the consumer forgot to
      bundle `sqlcipher_flutter_libs` on
      Flutter or `libsqlcipher` on desktop).

    * `isSqlCipherAvailable()` top-level
      function in
      `lib/src/sqlite/sqlcipher_probe.dart`.
      The probe was previously a private
      helper inside
      `test/sqlite/encrypted_db_test.dart`;
      it is now part of the public API. The
      result is cached at the isolate level
      (the cost is paid at most once per
      process). A test-only
      `debugResetSqlCipherProbeCache()` clears
      the cache.

    * `Db.isOpen` getter on `Db`. Thin
      wrapper over
      `SqliteQueryProvider.isOpen` (which
      tracks a `_disposed` flag set by
      `disposeAsync`).

    * `Db.diagnostics()` method on `Db`.
      Returns a `Map<String, Object?>` with
      `isOpen`, `encrypted`, `encryptionStatus`,
      `keySource` (`'password' | 'keyProvider'
      | 'none'`), and `encryptionConfig` (the
      four SQLCipher tunables as a map, or
      `null`). The map is easy to log to JSON,
      post to a debug endpoint, or print. The
      map never contains the resolved password
      — only the key source — so it is safe
      to forward to a server-side audit log.

  `Db` is now constructed with the original
  `password` / `keyProvider` /
  `encryptionConfig` arguments tracked
  (previously it discarded them after
  resolving the key). The tracking is what
  `diagnostics()` needs; the resolved
  password itself is not stored, to keep the
  key out of long-lived memory.

* **Doc cleanups.** Two small, hygiene-only
  changes bundled with the rest of the
  polish: the Spanish doc comments in
  `lib/src/rest/interceptor.dart` and
  `lib/src/rest/error.dart` are translated to
  English (the rest of the codebase is in
  English; these two files were the only
  outliers), and the README bullet that said
  "989 unit and integration tests" is updated
  to the actual current count. The FAQ gains
  two new entries under the Security section:
  "How do I check whether the engine is
  actually SQLCipher?" (about
  `isSqlCipherAvailable`) and "How do I tell,
  at runtime, whether my DB is encrypted?"
  (about `Db.diagnostics` and
  `EncryptionStatus`).

* **New tests** in
  `test/sqlite/encryption_ecosystem_test.dart`
  (10 new cases): `Db.isOpen` (open + closed),
  `Db.diagnostics` (plain, password,
  keyProvider, config, closed, status with
  or without SQLCipher), and
  `isSqlCipherAvailable` (cached value, debug
  reset). The full
  `encryption_ecosystem_test.dart` file goes
  from 29 to 39 cases.

No breaking changes; the `password:` parameter
from 1.0.5 is unchanged. `keyProvider:`
is mutually exclusive with `password:` (passing
both raises `ArgumentError`). The full 1.0.5
test suite (756 tests) still passes, plus the
29 new ones, plus the 1 libsqlcipher round-trip
test that is skipped without the engine.

## [1.0.5] — 2026-06-15

Patch release. Adds optional, end-to-end encryption
of the local SQLite database via SQLCipher. Existing
callers that do not opt in are unaffected.

* **Encrypted database support.**
  `Db.open` and `Db.inMemory` now accept an optional
  `password` parameter that is forwarded to the
  underlying SQLite engine as `PRAGMA key` after
  open. The same parameter is exposed on
  `SqliteQueryProvider.file` and
  `SqliteQueryProvider.inMemory` for advanced users.
  The default (`password: null`) preserves the
  1.0.x behavior — plain SQLite, no key — so this
  change is fully backward compatible.

* **Single-quote escaping.** Passwords that contain
  `'` characters are escaped by doubling
  (`O'Brien` → `O''Brien`) before being interpolated
  into the `PRAGMA key = '...'` literal. The escape
  is applied by a single private helper,
  `SqliteQueryProvider._applyPragmaKey`.

* **Open-time wrong-password detection.** After
  running `PRAGMA key`, the provider issues a
  verification query
  (`SELECT count(*) FROM sqlite_master`) and closes
  the connection with a `DatabaseException` if the
  first encrypted page cannot be decrypted. The
  exception message is explicit about the three
  possible causes (wrong password, non-SQLCipher
  file, engine is not SQLCipher) and links to
  `doc/13-faq.md` for the engine setup. This avoids
  the alternative failure mode where the database
  appears to open successfully and then returns
  garbage on the first read.

* **Engine responsibility is the consumer's.**
  `d_rocket` does not bundle a SQLCipher build.
  The consumer installs `sqlcipher_flutter_libs`
  on Flutter, or `libsqlcipher` system-wide on
  desktop, and the `PRAGMA key` is then effective.
  A vanilla SQLite engine silently ignores
  `PRAGMA key`, so the parameter is a no-op
  without a SQLCipher native library. The
  documentation in `doc/13-faq.md` (new "Security"
  section) covers the platform setup in detail.

* **New tests** in
  `test/sqlite/encrypted_db_test.dart`:
    * The `password` parameter is accepted on
      `Db.open`, `Db.inMemory`,
      `SqliteQueryProvider.file`, and
      `SqliteQueryProvider.inMemory`
      (compile checks).
    * A password containing a single quote is
      escaped and does not produce a syntax error.
    * Opening without a `password` continues to
      work (back-compat, no behavior change).
    * An end-to-end round-trip
      (open → `CREATE TABLE` → `INSERT` → close →
      reopen → read) and a wrong-password
      rejection are gated on a runtime probe for
      `libsqlcipher`; on hosts without the engine
      they are skipped with an explanatory message.

* **Cookbook recipe rewritten.** The "Database
  encryption (SQLCipher)" entry in
  `doc/12-cookbook.md` previously documented an
  `SqliteEncryption(...)` API that does not exist
  in the package; the recipe has been rewritten
  to use the actual `password:` parameter on
  `Db.open`, and now links to the Security
  section of the FAQ for the engine setup and
  the `PRAGMA rekey` recipe.

* **Threat-model section added to the FAQ.**
  `doc/13-faq.md` now has a "What does SQLCipher
  protect against — and what doesn't it?" entry
  that enumerates the realistic protection
  boundary (file at rest, backups, page HMAC,
  weak-password brute force) and the realistic
  non-protection boundary (root on a running
  device, the keychain itself, data in transit,
  the application process, side channels, a
  stolen unlocked device). The short mental
  model at the end ("SQLCipher makes a copied
  file unreadable without the key") is the line
  the docs want a security reviewer to walk away
  with.

## [1.0.4] — 2026-06-14

Patch release. Lifts the restriction
that primary keys in `@Table` entities had
to be `int`. UUID (and other non-`int`)
primary keys are now supported, and
auto-incrementing `String` PKs are filled
with a UUID v4 at INSERT time.

* **Non-`int` primary keys (DDL).**
  `EntityMeta._columnDdl` in
  `lib/src/orm/entity_meta.dart` previously
  emitted `INTEGER PRIMARY KEY` for every
  primary key, regardless of the field's
  Dart type. A
  `@PrimaryKey(autoIncrement: false) String id`
  field — the typical UUID pattern —
  therefore generated `id INTEGER PRIMARY
  KEY` in the `CREATE TABLE` DDL, which
  then failed at insert time when a UUID
  string was passed. The DDL now uses the
  field's actual SQLite type for
  non-auto-incrementing PKs, so a `String`
  PK produces `id TEXT PRIMARY KEY`, a
  `DateTime` PK produces
  `started_at TEXT PRIMARY KEY`, and so
  on. `int` PKs with `autoIncrement: true`
  still emit
  `INTEGER PRIMARY KEY AUTOINCREMENT`
  (SQLite's `AUTOINCREMENT` is restricted
  to `INTEGER PRIMARY KEY`, so that branch
  is unchanged). For `isAutoIncrement: true`
  on a non-`int` type, the column is
  `<type> PRIMARY KEY` (no `AUTOINCREMENT`
  keyword) and the runtime fills the value.

* **Auto-incrementing `String` PKs are
  filled with a UUID v4.** When a
  `@PrimaryKey()` (default
  `autoIncrement: true`) is on a `String`
  field and the entity is inserted without
  a value set for that field, `DbSet.insertOne`
  in `lib/src/orm/db_set.dart` now
  generates a UUID v4 via the new
  `generateUuidV4()` helper (also exported
  from the package) and writes it back
  through the codegen-supplied `meta.setId`
  closure. The column DDL is
  `id TEXT PRIMARY KEY` (see above). The
  new helper is backed by `Random.secure()`
  and produces RFC 4122 v4 UUIDs
  (`xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx`
  with `y` in `8`/`9`/`a`/`b`).

* **`@PrimaryKey` docstring updated** in
  `lib/src/orm/primary_key.dart` to
  document the supported field types and
  the `autoIncrement` semantics, including
  the "runtime fills the value for non-`int`
  PKs" behavior.

* **New unit tests** in
  `test/orm_runtime_test.dart`:
    * `String` PK with
      `autoIncrement: true` emits
      `id TEXT PRIMARY KEY` and does not
      emit `AUTOINCREMENT`.
    * `String` PK with
      `autoIncrement: false` (the previous
      patch) still emits
      `id TEXT PRIMARY KEY`.
    * `DateTime` PK emits
      `started_at TEXT PRIMARY KEY`.
    * `generateUuidV4()` returns a valid
      RFC 4122 v4 UUID and consecutive
      calls do not collide.

No behavior change for existing `int` PKs.
For non-`int` PKs the generated
`CREATE TABLE` DDL is now correct instead
of broken, and for
`autoIncrement: true` `String` PKs the
runtime generates a UUID v4 so callers
no longer need to set a value before
`saveChanges`.

## [1.0.3] — 2026-06-14

Patch release. Lifts the restriction that
primary keys in `@Table` entities had to be
`int`. UUID (and other non-`int`) primary
keys are now supported.

* **Non-`int` primary keys.** `EntityMeta._columnDdl`
  in `lib/src/orm/entity_meta.dart` previously
  emitted `INTEGER PRIMARY KEY` for every
  primary key, regardless of the field's
  Dart type. A `@PrimaryKey(autoIncrement: false)
  String id` field — the typical UUID pattern
  — therefore generated `id INTEGER PRIMARY KEY`
  in the `CREATE TABLE` DDL, which then failed
  at insert time when a UUID string was passed.
  The DDL now uses the field's actual SQLite
  type for non-auto-incrementing PKs, so a
  `String` PK produces `id TEXT PRIMARY KEY`,
  a `DateTime` PK produces `created_at TEXT
  PRIMARY KEY`, and so on. `int` PKs with
  `autoIncrement: true` still emit
  `INTEGER PRIMARY KEY AUTOINCREMENT` (SQLite's
  `AUTOINCREMENT` is restricted to `INTEGER
  PRIMARY KEY`, so this branch is unchanged).

* **`@PrimaryKey` docstring updated** in
  `lib/src/orm/primary_key.dart` to document
  the supported field types and the
  `autoIncrement` semantics.

* **New unit test** in
  `test/orm_runtime_test.dart` covering
  `String` and `DateTime` primary keys.
  Existing `int` PK tests are unchanged and
  still pass.

No runtime behavior changes for `int` PKs.
For non-`int` PKs the generated `CREATE TABLE`
DDL is now correct instead of broken.

## [1.0.3] — 2026-06-14

Patch release. Two changes:

* **`CREATE TABLE` now uses `IF NOT EXISTS`.**
  `EntityMeta.createTableDdl()` in
  `lib/src/orm/entity_meta.dart` previously
  emitted `CREATE TABLE $tableName (`
  unconditionally. On a fresh database this is
  fine, but any re-run of the migration on an
  existing database (e.g. a development
  reset that left tables behind, or a hot-reload
  in Flutter) threw `SqliteException(1):
  table X already exists`. The 3 unit tests
  that asserted the old `CREATE TABLE X` prefix
  were updated to assert the new
  `CREATE TABLE IF NOT EXISTS X` prefix. The
  behavior change is purely additive — the
  fresh-install path is unchanged (SQLite
  creates the table), and the re-run path is
  now a no-op (SQLite sees the table and
  skips).
* **README doc links dropped the
  `packages/d_rocket/` prefix.** The 14 doc
  links in the README's "Docs" section (and
  the 3 inline cross-references) pointed to
  `packages/d_rocket/doc/` in the monorepo.
  They now point to `doc/` at the repo root
  (e.g.
  `https://github.com/torogoz-tech/d_rocket/blob/main/doc/01-overview.md`).
  This is the URL shape the project README
  ships with on pub.dev.

No API or behavior changes.

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
