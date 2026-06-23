# FAQ

Common questions, gotchas, and performance notes.

---

## General

### What is `d_rocket`?

A unified framework for the data layer of Dart/Flutter
applications. It bundles serialization, REST, LINQ,
ORM, sync, and realtime into one package, with a
single annotation-driven generator.

### Why a single package?

A typical Dart/Flutter app assembles its data layer
from half a dozen different packages. Each has its own
annotation style, its own error model, its own dialect.
`d_rocket` replaces that with one mental model and one
generator.

### Why annotation-driven?

Annotations are a clean way to express intent without
boilerplate. The framework can read the annotations
and generate the wiring (serializers, REST clients,
ORM metadata) automatically. The alternative — manual
`registerAll(...)` calls in every file — is what the
codegen is replacing.

### Why is the SQLite engine bundled?

Most apps want SQLite. Bundling it removes a layer of
indirection: `package:sqlite3` is the only engine
shipped out of the box. If you want a different
engine, the `AsyncQueryProvider` contract is open for
you to implement your own provider.

### Is `d_rocket` stable?

Yes. As of 1.0.0, the public API is frozen within the
`1.x` series. Patch versions fix bugs; minor versions
add features; major versions (2.x, 3.x) introduce
breaking changes. The migration guides will be in
this document for each major bump.

### What's the license?

MIT. See [LICENSE](../LICENSE).

---

## Installation and setup

### `dart pub get` fails

The most common cause is an out-of-date SDK. The
minimum is `Dart 3.5.0` and `Flutter 3.10.0`. If you
have older versions, upgrade:

```bash
flutter upgrade
```

### `dart run build_runner build` doesn't generate anything

The runner has no annotations to process. Make sure
your classes are annotated with `@Serializable`,
`@RestClient`, or `@Table`, and that the files
are in `lib/`.

### `dart run build_runner build` regenerates on every run

This is a known non-determinism issue. The fix is
usually:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

Run this from a clean checkout (delete `.dart_tool/`
first if needed).

### I see "Could not resolve package"

Make sure your `pubspec.yaml` has both `d_rocket` (in
`dependencies`) and `d_rocket_builder` (in
`dev_dependencies`). Also run `dart pub get` to refresh
the package config.

### The generated files have errors

Re-run the generator:

```bash
dart run build_runner build --delete-conflicting-outputs
```

If the error persists, your `analyzer` may be out of
date:

```yaml
dev_dependencies:
  analyzer: ^8.0.0
```

---

## Migration from other frameworks

### I was using `d_serializer` 1.3.0

Switch to `d_rocket` 1.0.0. Replace
`package:d_serializer/d_serializer.dart` with
`package:d_rocket/d_rocket.dart`. The annotation API
is unchanged; the only rename is `Serializer.fromJson`
→ `Serializer.fromJson<T>`. The dependency on
`d_serializer_builder` moves to `d_rocket_builder`.

### I was using `d_rest` 0.1.0

Switch to `d_rocket` 1.0.0. Replace
`package:d_rest/d_rest.dart` with
`package:d_rocket/d_rocket.dart`. The `@RestClient`
API is unchanged; resilience config moved from
`RestClientBuilder` to `RestConfig`, and the
`circuitState<T>()` extension moved to
`dRest.circuitState<T>()`.

### I was using sqflite

The `@Table` API is a higher-level abstraction
than sqflite's `db.execute()` + `db.query()` style.
You'll write less code, and the LINQ provider will
push your filters down to SQL. The migration path is:

1. Replace your `Database` / `Transaction` API calls
   with `DbSet<T>` chains.
2. Replace your hand-rolled `CREATE TABLE` SQL with
   `MigrationStrategy`.
3. Replace your manual JSON serialization with
   `@Serializable`.

### I was using json_serializable

The `@Serializable` annotation is similar in spirit to
`@JsonSerializable`. The main differences:

- `d_rocket` uses a central `Serializer` registry, not
  per-class `fromJson` constructors. This lets you do
  `Serializer.fromJson<T>(raw)` for arbitrary types.
- `d_rocket` supports sealed unions via
  `@SerializableUnion`.
- `d_rocket` has built-in support for custom `Format`s
  (decimal, date, enum, ID).

The migration is mostly mechanical. The codegen for
`d_rocket` is `d_rocket_builder`, not
`json_serializable`.

### I was using moor (drift)

The `DbSet<T>` API is similar to moor's `Table` API.
The LINQ provider is similar. The main difference:
`d_rocket` has a single annotation dialect for
serialization, REST, and the ORM, while moor uses
separate ones.

---

## Performance

### How does `d_rocket` perform compared to raw SQL?

The LINQ provider pushes down to SQL for every
translatable operator. For complex queries that don't
fit, use `db.exec(sql, params)` or
`db.rawQuery(sql, params)` to bypass the abstraction.

The change tracker in the ORM has a small per-row
overhead. For batch operations, use
`db.set<T>().addAll(...)` and `saveChanges()` once.

### How does `d_rocket` perform compared to `package:http`?

For raw HTTP, the framework is roughly equivalent to
`package:http` because it uses `package:http`
under the hood. The overhead is in the typed
interfaces, interceptors, and resilience — all of
which add a few microseconds per request.

For high-throughput endpoints, consider skipping the
`@RestClient` abstraction and using `package:http`
directly. Most apps don't need this — the framework
handles thousands of requests per second without
bottlenecking.

### Why is the codegen so slow?

`build_runner` re-emits every generated file on every
run. For a large project, this can take 10+ seconds.
To speed it up:

1. Use `build_runner watch` (it caches).
2. Use `build --build-filter` to scope the build to
   specific files.
3. Split your project into smaller packages; each
   builds independently.

### Why does my first `Db.open(path: 'app.db')` take 200ms?

The first open acquires a database connection, applies
migrations, and starts the change-tracker. Subsequent
opens are cached. For an in-memory `Db` (e.g.
in tests), the open is faster.

### Can I use `d_rocket` in an `Isolate`?

Yes. `Db.openSync(path: 'app.db')` opens a
synchronous database in an isolate. The
`IsolateWorker<Db>` helper handles the port
plumbing.

---

## Codegen

### My annotations are not being processed

The codegen reads files in `lib/` by default. If your
annotated files are in a sub-package, make sure that
sub-package exports them.

### The codegen fails with "X is not annotated"

You probably have a class that uses a generic type
parameter, and the codegen can't see the parameter's
runtime type. Add an explicit type parameter:

```dart
final list = Serializer.fromJson<List<Customer>>(raw);
```

### I want to write a custom builder

The codegen package `d_rocket_builder` uses
`build_runner` under the hood. You can write a
custom `Builder` that consumes the same annotation
graph.

### Why is there a `_g` suffix on generated files?

The convention is `*.g.dart` (generated) and
`*.rocket.g.dart` (specifically the `d_rocket`
generator). The `--delete-conflicting-outputs` flag
of `build_runner` looks for this suffix.

---

## Error model

### What does "the framework couldn't deserialize X" mean?

The runtime expected an `X` (per the registered
serializer) but the JSON didn't match. Common
causes:

- A field is missing in the JSON but required in the
  Dart class.
- A field has the wrong type (e.g. `String` vs `int`).
- A union discriminator is missing or has an unknown
  value.

The exception includes the path to the offending
field.

### What does "the LINQ chain can't be translated" mean?

The chain has an operator that the SQL provider
doesn't know how to translate. The exception includes
the failing chain segment. Fix the chain to use only
translatable operators, or fall back to
`db.exec(sql, params)`.

### What does "the migration checksum doesn't match" mean?

A migration was edited after it was applied. The
runner refuses to proceed. The recommended fix is to
add a new migration that performs the desired change
(see [10 — Migrations](10-migrations.md#the-history-table)).

---

## Misc

### Can I use `d_rocket` on the web?

The framework itself is platform-agnostic, but the
SQLite engine is not available on the web. The
recommended approach for a web build is to use an
in-memory `Db` for tests and a different data
layer (e.g. IndexedDB) for the web app. The
`AsyncQueryProvider` contract is open for you to
implement your own web-compatible provider.

### Can I use `d_rocket` on the server (Dart VM)?

Yes. `Db.open(path: '/var/data/app.db')` works
in a Dart VM context. For server-side apps, the
`AsyncQueryProvider` is open for you to use a
different engine (e.g. Postgres) by writing a custom
provider.

### Why isn't the codegen output in `.gitignore`?

It's a deliberate choice: the generated files are
checked in so that:

1. The framework works without running the codegen
   on a fresh checkout.
2. The CI can verify that the generated files are
   up-to-date (`build_runner build --delete-conflicting-outputs`).

If you prefer to keep them out of git, add
`**.g.dart` and `**/*.rocket.g.dart` to
`.gitignore`. The tradeoff is that every fresh
checkout needs to run the codegen before it can
build.

### How do I migrate between major versions?

Each major version (1.x → 2.x, etc.) ships a
migration guide in the changelog. The process is:

1. Bump the version constraint.
2. Read the migration guide.
3. Update your code (most of the changes are
   mechanical).
4. Re-run the codegen.
5. Run your tests.

### Where do I report a bug?

Open an issue on the
[GitHub repository](https://github.com/torogoz-tech/d_rocket/issues).

### How do I get help?

- Read this documentation.
- Search the [GitHub issues](https://github.com/torogoz-tech/d_rocket/issues)
  to see if your question has been asked.
- Open a new issue with the `question` label.

---

## Security

### How do I open an encrypted database?

Pass a `password` to `Db.open` or `Db.inMemory`. The
`password` is forwarded to the SQLite engine as a
`PRAGMA key`. d_rocket does the escape (`'O''Brien'`)
and runs a small verification query
(`SELECT count(*) FROM sqlite_master`) to surface
wrong-password errors at open time instead of at
first read.

```dart
dRocketSqlite();
final db = await Db.open(
  path: 'app.db',
  password: 'correct horse battery staple',
);
```

> **You must bundle a SQLCipher build of the native
> library.** d_rocket does not switch engines on its
> own. On Flutter, swap `sqlite3_flutter_libs` for
> `sqlcipher_flutter_libs`. On desktop, install
> `libsqlcipher` system-wide. The `PRAGMA key` is a
> silent no-op on a vanilla SQLite engine, so an
> unencrypted build will not surface an error — it
> will just write plaintext to disk.

### How do I bundle SQLCipher on Flutter?

```yaml
# pubspec.yaml — replace sqlite3_flutter_libs with
# sqlcipher_flutter_libs. d_rocket itself only depends
# on package:sqlite3; the consumer is responsible for
# the native library.
dependencies:
  sqlcipher_flutter_libs: ^0.6.0
```

```dart
// main.dart — the import has the side effect of
// registering libsqlcipher with package:sqlite3's
// loader, so subsequent `sqlite3.open` calls load
// the SQLCipher binary.
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';

void main() async {
  await applyToCipherOpen(); // or whatever your
  // sqlcipher_flutter_libs version exposes; the
  // import is what matters.
  dRocketSqlite();
  dRocketSqlite();

  final db = await Db.open(path: 'app.db', password: '…');
  // …
}
```

### How do I bundle SQLCipher on desktop?

Install `libsqlcipher` system-wide and point
`package:sqlite3/open.dart`'s loader at it before
opening any database:

```dart
import 'dart:io';
import 'package:sqlite3/open.dart';

void main() async {
  if (Platform.isMacOS) {
    open.overrideFor(
      OperatingSystem.macOS,
      () => DynamicLibrary.open('libsqlcipher.dylib'),
    );
  } else if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlcipher.so'),
    );
  } else if (Platform.isWindows) {
    open.overrideFor(
      OperatingSystem.windows,
      dRocketSqlite();
      () => DynamicLibrary.open('sqlcipher.dll'),
    );
  }
  dRocketSqlite();

  final db = await Db.open(path: 'app.db', password: '…');
  // …
}
```

> `homebrew install sqlcipher`,
> `apt install libsqlcipher-dev`,
> `choco install sqlcipher`. The `overrideFor` call
> must run before the first `Db.open`.

### What about raw keys (256-bit)?

`PRAGMA key` accepts both passphrases and raw 256-bit
keys. Pass the `x'…'` form as the `password`
dRocketSqlite();
string — d_rocket escapes single quotes by doubling
and forwards the literal to SQLCipher:

```dart
final db = await Db.open(
  path: 'app.db',
  password: "x'2DD29CA851E7B56E4697B0E1F08507293"
             "D761A05CE4D1B628663F411A8086D99'",
);
```

### What happens if the password is wrong?

`Db.open` throws a `DatabaseException` at open time
(the verification query
`SELECT count(*) FROM sqlite_master` returns
`SQLITE_NOTADB` because the page can't be decrypted).
The error message links back to this FAQ section so
the cause is obvious:

```
DatabaseException: Failed to open encrypted database:
the password is incorrect, the file is not a SQLCipher
database, or the underlying engine is not SQLCipher.
```

### Can I change the password of an existing database?

Yes. `db.changePassword(newPassword: '...')` wraps
`PRAGMA rekey` with the same single-quote escape used
by the open path. The new key can also be supplied
via a `KeyProvider` (`newKeyProvider: ...`); the two
dRocketSqlite();
are mutually exclusive and the same `ArgumentError`
pattern from `Db.open` applies.

```dart
final db = await Db.open(
  path: 'app.db',
  password: oldPassword,
);
await db.changePassword(newPassword: newPassword);
await db.close();
```

The `rekey` is applied to every page; for a
multi-megabyte database it can take a few hundred
milliseconds. Plan a one-time migration (open →
`changePassword` → close) and document it in your
release notes. The current connection stays open
across the rekey, so the user can keep working with
the same `Db` instance.

### Can I encrypt only some columns?

`d_rocket` does not bundle a column-level encryption
helper, but the pattern is straightforward: encrypt
the field in Dart before `add`, decrypt in the
`fromRow` closure. The library stays the same.

### Can I read the key from platform secure storage?

Yes. `Db.open` and `Db.inMemory` accept a
`keyProvider:` parameter (mutually exclusive with
`password:`). The provider is awaited once per open,
so the value is re-read from the keychain on every
restart. `d_rocket` ships two built-in providers for
tests and the simple case (`StaticKeyProvider` and
`CallbackKeyProvider`); consumers that integrate
with `flutter_secure_storage` (or any other vault)
implement the `KeyProvider` interface in five lines
on the application side:

```dart
class FlutterSecureStorageKeyProvider implements KeyProvider {
  FlutterSecureStorageKeyProvider(this._storage, {required this.account});
  final FlutterSecureStorage _storage;
  final String account;

  @override
  Future<String> readKey() async {
    final String? key = await _storage.read(key: account);
    if (key == null) {
      dRocketSqlite();
      throw StateError('No key in secure storage for account "$account"');
    }
    return key;
  }
}

final db = await Db.open(
  path: 'app.db',
  keyProvider: FlutterSecureStorageKeyProvider(
    FlutterSecureStorage(),
    account: 'd_rocket_key',
  ),
);
```

`d_rocket` does not cache the value across opens, so
rotating the key in the keychain takes effect on the
next `Db.open`.

### Can I tune the SQLCipher PRAGMAs (KDF iterations, page size, HMAC)?

Yes. Pass an `EncryptionConfig` to `Db.open` (or
`Db.inMemory`) alongside `password:` or `keyProvider:`.
The config wraps the four most common SQLCipher
tunables:

```dart
const EncryptionConfig config = EncryptionConfig(
  kdfIterations: 1000000, // default 256000
  dRocketSqlite();
  pageSize: 8192,         // default 4096
  hmacUse: true,          // default true
  memorySecurity: true,   // default true
);

final db = await Db.open(
  path: 'app.db',
  password: '…',
  encryptionConfig: config,
);
```

The four PRAGMAs
(`cipher_default_kdf_iter`, `cipher_page_size`,
`cipher_use_hmac`, `cipher_memory_security`) are
applied right after `PRAGMA key` (the order SQLCipher
requires) and before the open-time verification
query. The config is validated at construction
time: a bad `kdfIterations` or `pageSize` raises
`ArgumentError` before the engine is touched, so
configuration errors surface as Dart-level errors
rather than `SqliteException`.

Caveat: `pageSize` only takes effect on a fresh
database. Changing the page size on an existing
encrypted database requires a `PRAGMA rekey` flow
(typically `changePassword` plus a dump/restore).

### I want to log the SQL I send to the engine — but the password might leak

Use `redactPragmaKey(sql)`. It replaces the literal
value of any `PRAGMA key = '...'` or
`PRAGMA rekey = '...'` in the input with `'***'`:

```dart
log('executed: ${redactPragmaKey(sql)}');
// PRAGMA key = 'hunter2'
// -> PRAGMA key = '***'
```

The function is case-insensitive, tolerates extra
whitespace, and correctly handles the single-quote
escape d_rocket uses internally (`O''Brien` becomes
`'***'`, not `O'''`). It does not try to detect
bound-parameter form (`PRAGMA key = ?`) because
`PRAGMA` does not accept bound parameters in
SQLite.

### How do I check whether the engine is actually SQLCipher?

`isSqlCipherAvailable()` opens a short-lived
in-memory database with a deliberately wrong
password and reports `true` only if the engine
rejects the key (the `SQLITE_NOTADB` that
SQLCipher raises on the verification query). On
a vanilla SQLite build, the `PRAGMA key` is
silently ignored and the probe returns `false`.

The result is cached at the isolate level, so the
cost is paid at most once per process. Use it
inside a "first run" guard:

```dart
if (!isSqlCipherAvailable() && db.diagnostics()['encrypted'] == true) {
  // ...
}
```

(`db.diagnostics()` reports the result as the
`encryptionStatus` field, which is
`EncryptionStatus.encrypted` on a SQLCipher build
and `EncryptionStatus.unknown` on a vanilla SQLite
build where the probe could not confirm the
engine.)

### How do I tell, at runtime, whether my DB is encrypted?

`db.diagnostics()` returns a snapshot of the
current connection state. The map contains at
least:

* `isOpen: bool` — the same as `db.isOpen`.
* `encrypted: bool` — `true` if the connection
  was opened with a `password:` or `keyProvider:`.
* `encryptionStatus: EncryptionStatus` — the
  posture (`plain`, `encrypted`, or `unknown`).
* `keySource: 'password' | 'keyProvider' | 'none'`
  — which input produced the key.
* `encryptionConfig: Map<String, Object?>?` — the
  four SQLCipher tunables, or `null` if no
  config was passed.

The map is plain `Map<String, Object?>`, so it is
easy to log to JSON, post to a debug endpoint,
or print. The map never contains the resolved
password — only the key source.

### What does SQLCipher protect against — and what doesn't it?

SQLCipher is at-rest encryption for the database
file. The protection boundary is well-defined and
worth being explicit about, because the right
answer for a security review is rarely "use
SQLCipher and you're done".

**SQLCipher protects against:**

- **Filesystem access on an unlocked device.**
  An attacker who pulls the `.db` file (via a
  forensic image, a stolen unlocked phone, a
  misplaced laptop, or a backup) and has *only*
  the file cannot read the data without the
  password.
- **Backups.** The same property holds for any
  backup medium (iCloud, Google Drive, ADB pull)
  that copies the file but not the keychain.
- **Single-page tampering.** SQLCipher includes an
  HMAC over each page (default-on in 4.x); a
  flipped bit in the file is detected on first
  read and raises `SQLITE_NOTADB`.
- **Weak passwords via brute force.** PBKDF2-HMAC-
  SHA512 with 256,000 iterations by default makes
  each guess expensive. (You can raise the
  iteration count — see the FAQ entry on
  `PRAGMA cipher_default_kdf_iter` once the
  `EncryptionConfig` helper lands.)

**SQLCipher does NOT protect against:**

- **Root / admin access on a running device.**
  If the attacker can run code as root while
  the database is open, they can dump the key
  out of process memory. The protection is
  *at rest*, not *in use*. (Mitigation: keep the
  DB closed when not in use; close on
  background; rely on the OS's secure storage
  for the key.)
- **The keychain.** The key ultimately lives in
  the OS's secure storage (Keychain, Keystore,
  libsecret). If the attacker has the keychain,
  they have the key, and therefore the database.
  Pick a keychain that the OS actually protects
  (Keychain with `kSecAttrAccessibleWhenUnlocked`
  and a passcode set; Keystore-backed StrongBox
  when available).
- **Data in transit.** SQLCipher is for files
  on disk. If you sync the file to a server,
  the connection must be TLS. If you replicate
  the rows over the wire (e.g. via the sync
  layer), that channel needs its own encryption
  and authentication.
- **The application process.** A memory
  corruption bug, a Dart-level SQL injection,
  or a malicious dependency can read or write
  the database with full SQLCipher privileges,
  because the engine is loaded in the same
  process. SQLCipher is not a sandbox; it is
  a vault for the *file*.
- **Side channels.** Timing attacks on the
  password check are mitigated (SQLCipher uses
  constant-time comparisons), but power
  analysis, acoustic emanation, and rowhammer-
  class attacks are out of scope.
- **Wiping a stolen device.** If the attacker
  has the device, they have the file. SQLCipher
  only helps if the file is the *only* thing
  they get; a screen-unlocked phone gives them
  the running process, the keychain, and the
  file.

**The 30-second mental model:** SQLCipher makes a
copied file unreadable without the key. It does
not make a running process unreadable, a stolen
device safe, or an insecure channel private.
dRocketSqlite();
For those, you need a passcode on the device, a
hardware-backed keychain, and TLS in flight.

## Auto-migrations (1.2.0+)

### How do I turn on auto-migrations?

```dart
final db = await Db.open(
  path: 'app.db',
  entityMetas: <EntityMeta>[
    Patient.entityMeta,
    Observation.entityMeta,
  ],
  autoMigrate: true,
);
```

`Db.open` and `Db.inMemory` gain two new
parameters: `entityMetas:` (the list of
codegen-emitted entity metas) and
`autoMigrate: bool`. When both are set, the
runtime computes the diff between the
codegen schema and the last applied schema
on disk, applies the safe changes in a
single transaction, and reports the unsafe
changes. Existing callers that do not pass
`entityMetas:` see no change in behaviour.

### What counts as a "safe" change?

CREATE TABLE (new entity), CREATE INDEX
(new `@Index`), and ADD COLUMN (nullable
or with a default literal). Everything
else is unsafe and is reported, not
applied:

- DROP TABLE, DROP COLUMN, DROP INDEX.
- MODIFY COLUMN: a change in type,
  nullability, default literal, or
  foreign-key target. SQLite has no
  ALTER COLUMN; the migration requires a
  table rebuild.
- The rename heuristic: a DROP + an ADD
  of the same name with the same type and
  nullability is reported as a possible
  RENAME (the user has to confirm manually
  because the heuristic can be wrong).

The conservative default: the auto-migrator
never destroys data silently. The user is
expected to handle unsafe changes
explicitly (typically by writing a
hand-rolled migration that performs the
unsafe change).

### How do I see the pending diff without applying it?

```dart
final pending = await db.pendingSchemaDiff();
for (final diff in pending) {
  print('${diff.severity}: ${diff.tableName}'
        '.${diff.columnName ?? "<table>"} '
        '(${diff.type})');
  print('  reason: ${diff.reason}');
  print('  sql:    ${diff.sql}');
}
```

`db.pendingSchemaDiff()` returns the diff
without applying anything. Useful for
logging, dry-runs, and CI checks that
fail when there are unhandled unsafe
diffs. The diff is also returned by
`db.runAutoMigrations()` in the
`AutoMigrationResult.unsafe` list.

### How do I run the auto-migration on demand?

```dart
final result = await db.runAutoMigrations();
print('applied: ${result.applied.length}');
print('unsafe:  ${result.unsafe.length}');
print('snapshot is now: ${result.snapshot}');
```

`Db.runAutoMigrations()` is called
automatically by `Db.open(autoMigrate: true)`.
The version that takes no arguments can
also be called from a custom Db lifecycle
(e.g. a background task that runs the
migration outside the open path).

### What happens to the schema_state when there are unsafe diffs?

The safe diffs are applied, but the new
snapshot is NOT written to the
`d_rocket_schema_state` table. The unsafe
diffs keep showing up in
`db.pendingSchemaDiff()` on every reopen
until the user handles them (typically by
writing a hand-rolled migration that
performs the unsafe change explicitly,
then re-opening). This is intentional: a
pending unsafe diff is a louder signal
than a pending safe change, and we want
the user to handle the unsafe first.

### Can I use auto-migrations and hand-written migrations together?

Yes. The auto-migrator runs AFTER any
hand-written `MigrationStrategy`. The two
do not share data: the hand-written
migrations are tracked in the existing
`_d_rocket_migrations` table; the
auto-migration snapshot is stored in the
new `d_rocket_schema_state` table. A
typical pattern is: hand-written
migrations for the initial schema and
for one-off data migrations, then
auto-migrations for the steady-state
add-column / add-index work.

### How does the auto-migrator know what the schema is?

The runtime computes the schema snapshot
from the `EntityMeta` list you pass to
`Db.open(entityMetas: ...)`. The codegen
emits one `EntityMeta` per `@Table` class
(it is a `static const` field on the
generated `*EntityMeta` class). The
runtime walks the list, flattens
embedded fields and TPH subclass
columns, and produces a JSON-serializable
`SchemaSnapshot`. The diff is then
computed against the last applied
snapshot (from the `d_rocket_schema_state`
table) and applied.
