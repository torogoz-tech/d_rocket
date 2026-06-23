# CLI tools

The framework ships two CLI executables that work with
the `dart run` tool. Both are added to your `PATH`
when you depend on `d_rocket`; you don't need to
install anything globally.

---

## `d_rocket:migration`

Scaffolder and validator for `Migration` classes.

### `add <name>`

Scaffold a new migration with the right id, class name,
and pre-filled `up()` / `down()` bodies:

```bash
$ dart run d_rocket:migration add create_inventory_table
✅ Created lib/db/migrations/M005_create_inventory_table.dart
   id: 005, class: M005CreateInventoryTable
```

The `<name>` is the human-readable name (snake_case
or kebab-case both work). The scaffolder picks the
next id by scanning the existing migrations.

By default, files are created under
`lib/db/migrations/`. Override with the
`D_ROCKET_MIGRATIONS_DIR` environment variable:

```bash
$ D_ROCKET_MIGRATIONS_DIR=lib/database/migrations \
    dart run d_rocket:migration add create_inventory_table
```

For the `id`, the scaffolder supports:

- 3-digit zero-padded (the default: `005`, `006`, ...).
- Date-based (`YYYY-MM-DD-NNN`): pass `--date` and
  the scaffolder uses today's date as the prefix.
- Custom: pass `--id <id>` to override the
  auto-generated id.

The generated file is a skeleton:

```dart
class M005CreateInventoryTable extends Migration {
  @override
  String get id => '005';

  @override
  int get version => 5;

  @override
  String get name => 'create_inventory_table';

  @override
  void up(MigrationExecutor exec) {
    // TODO: implement up.
  }

  @override
  void down(MigrationExecutor exec) {
    // TODO: implement down.
  }
}
```

### `doctor`

Validate the migration history:

```bash
$ dart run d_rocket:migration doctor
✅ Migration history is contiguous (5 migrations).
```

The doctor checks for:

- **Gaps** in the sequence (e.g. `001`, `003` but no `002`).
- **Duplicate ids** or versions.
- **Checksum mismatches** between the source and the
  applied history (requires a database connection —
  pass `--db <path>` to point at a specific db).
- **Missing files** (the strategy references a class
  that doesn't exist on disk).

For a JSON-friendly output, use `--format json`:

```bash
$ dart run d_rocket:migration doctor --format json
{
  "ok": true,
  "count": 5,
  "issues": []
}
```

For a CI-friendly exit code, use `--strict` (exits
non-zero on any issue):

```bash
$ dart run d_rocket:migration doctor --strict
```

### `list`

List the discovered migrations in order:

```bash
$ dart run d_rocket:migration list
001  M001CreateTodos           (v1)
002  M002AddTodosDueDate       (v2)
003  M003CreateCustomers       (v3)
004  M004CreateOrders          (v4)
005  M005CreateInventoryTable  (v5)
```

With `--format json`, the same data is emitted as a
JSON array for tooling consumption.

### `verify <id>`

Verify a specific migration's checksum matches the
applied history:

```bash
$ dart run d_rocket:migration verify 005
✅ M005CreateInventoryTable matches the applied history.
```

This is useful in CI to confirm no migration has been
silently edited.

### `check` (2.0.0)

Compute the pending schema diff between your codegen-
supplied entity metas and the actual schema in a
SQLite database. Surfaces unsafe diffs (e.g.
`DROP TABLE`) so you can fix them before merging.
CI-friendly: exits with code 1 when any unsafe
diff is found.

```bash
$ dart run d_rocket:migration check \
    --db app.db \
    --entities lib/db/entities.dart
🔎 Computing schema diff...
   db: /abs/path/app.db
   entities: lib/db/entities.dart

✅ Schema is in sync (no diffs).
# exit code 0
```

When there are diffs, the output lists each one
with severity, type, target, SQL, and reason:

```
Found 2 diff(s) (1 safe, 1 unsafe):
  ✓  SAFE     createTable on users
            sql:    CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)
            reason: New entity; CREATE TABLE IF NOT EXISTS is idempotent and non-destructive.
  ❌ UNSAFE   dropTable on legacy_audit_log
            sql:    DROP TABLE legacy_audit_log
            reason: Entity removed from code; dropping the table would lose all its data. Confirm
                    manually and write a hand-rolled migration that does the drop explicitly.

❌ 1 unsafe diff(s) found. Resolve before merging: write a hand-rolled migration that
performs the unsafe operation explicitly (auto-migrator does NOT auto-apply unsafe diffs).
# exit code 1
```

#### `--entities <dart_file>`

The entities file is a small Dart file the user
writes that exports a top-level
`List<EntityMeta> entityMetas`:

```dart
// lib/db/entities.dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/models/user.dart';
import 'package:my_app/models/order.dart';

final List<EntityMeta> entityMetas = <EntityMeta>[
  User.entityMeta,
  Order.entityMeta,
];
```

The CLI validates that the file exists and declares
`entityMetas` before spawning the worker.

#### `--db <path>`

The path to the SQLite database file to compare
against. Required.

#### Implementation

Under the hood, the CLI writes a temp worker
under `.d_rocket/check_worker.dart` and runs it
as a `dart run` subprocess. The worker uses the
user's `pubspec.yaml` to resolve
`d_rocket` + `d_rocket_engine_sqlite`, computes
the diff via `AutoMigrator.computePendingDiff()`,
and emits the diff as JSON between
`DR_CHECK_JSON_BEGIN` / `DR_CHECK_JSON_END`
markers. The CLI parses the JSON, prints a
human-readable summary, and exits 0 / 1
based on the unsafe-diff count.

The temp worker is gitignored by convention
(`.d_rocket/`). Re-running `check` overwrites
it; no stale state.

#### Supported engines (2.0.0)

- ✅ **SQLite** (`d_rocket_engine_sqlite`).
- ⏸️ Postgres + web engines: supported
  programmatically via `db.pendingSchemaDiff()`,
  but the CLI is SQLite-only in 2.0.0 (the worker
  hardcodes `SqliteQueryProvider.file(...)`).
  Postgres/web CLI support is a 2.1 item.

---

## `d_rocket:closure`

Closure → `Expr` translator. Useful for prototyping
queries that you want to later wire up to the codegen
sugar (`d_rocket_builder:closure`).

```bash
$ dart run d_rocket:closure '(t) => t.status == 0 && t.name.startsWith("a")'
Expr.lambda(
  <Expr>[Expr.param('t')],
  Expr.binary('&&',
    Expr.binary('==',
      Expr.member(Expr.param('t'), 'status'),
      Expr.const_(0),
    ),
    Expr.call(
      Expr.member(Expr.param('t'), 'startsWith'),
      <Expr>[Expr.const_('a')],
    ),
  ),
)
```

Paste the closure literal, get the equivalent `Expr`
tree. The output is copy-pasteable into a
`where_(...)` call.

The translator supports:

- **Parameter references**: `(t) => t.x` → `Expr.param('t')`.
- **Constants**: `42`, `"foo"`, `true`, `null` → `Expr.const_(...)`.
- **Field access**: `t.x` → `Expr.member(Expr.param('t'), 'x')`.
- **Method calls**: `t.startsWith("a")` → `Expr.call(Expr.member(...), [...])`.
- **Binary operators**: `==`, `!=`, `<`, `<=`, `>`, `>=`,
  `&&`, `||`, `+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`.
- **Unary operators**: `!`, `-`, `~`.
- **Ternary**: `cond ? a : b` → `Expr.conditional(cond, a, b)`.
- **Null-aware**: `t?.x` → `Expr.member(Expr.param('t'), 'x', nullable: true)`.

The translator does not (currently) support:

- **Generic types**: `(t) => t.items.length > 0` is fine
  (it just chains method calls), but explicit type
  parameters are not parsed.
- **String interpolation**: `` `hello ${name}` `` — use
  the explicit `Expr.binary('+', ...)` form.
- **Closures inside closures**: `(t) => t.items.any((i) => i.x)`
  parses as a single expression, but the inner closure
  isn't translated. Build the outer tree first, then
  fill in the inner one by hand.

For anything the translator can't handle, you can
always write the `Expr` tree directly — that's the
canonical form.

---

## Code generators (`d_rocket_builder`)

In addition to the two CLI scaffolders above,
`d_rocket` ships six `build_runner` builders in
the companion `d_rocket_builder` package. They
are wired by `build.yaml` (which `d_rocket_builder`
publishes); consumers do not need to write any
configuration of their own — `dart run build_runner
build` picks them up automatically.

| Builder | Output suffix | Detects | Emits |
|---|---|---|---|
| `d_rocket_builder:record` | `.g.dart` | every `extends Record` class | `_<ClassName>Init` + `register<ClassName>Record()` |
| `d_rocket_builder:serializer` | `.d_rocket_serializer.g.dart` | every `@Serializable` class | `XFromJson` / `XToJson` + `register<X>Serializer()` |
| `d_rocket_builder:rest_client` | `.d_rocket_rest_client.g.dart` | every `@RestClient` abstract class | `_$<ClassName>` impl + `register<ClassName>RestClient()` |
| `d_rocket_builder:rocket_table` | `.d_rocket_orm.g.dart` | every `@Table` class | `static EntityMeta entityMeta` + `register<ClassName>EntityMeta()` |
| `d_rocket_builder:realtime` | `.d_rocket_realtime.g.dart` | every `@WebSocketClient` and `@SseClient` abstract class | `_$<ClassName>` extending `IOWebSocketClient` / `HttpSseClient` |
| `d_rocket_builder:rocket_migration` | `.d_rocket_migration.g.dart` | every `@Migration` top-level function | `_$<FunctionName>` `MigrationBase` subclass |
| `d_rocket_builder:record_registry` | `d_rocket_registry.g.dart` (per-package, not per-file) | all of the above across `lib/**.dart` | one `initializeD()` function that calls every `register<X>...()` |

The per-file builders use **distinct** `PartBuilder`
suffixes so a single Dart file can freely mix
`extends Record` + `@Serializable` + `@RestClient`
+ `@Table` + `@Migration` annotations without
build_runner output collisions (this is the
HANDOFF §6 fix).

### `d_rocket_builder:rocket_migration`

The migration codegen. Walks every `@Migration`
top-level function (and every `@Table` class in
the same library) and emits a
`MigrationBase` subclass for each function:

```dart
@Migration(id: '001', name: 'Initial schema')
MigrationBase initialSchema() => _$_InitialSchema();
```

The generated `_$_InitialSchema` extends
`MigrationBase` and runs:

* `up()` — `entityMeta.createTableDdl()` + every
  `entityMeta.createIndexStatements()` for every
  `@Table` in the same library, then
  `PRAGMA foreign_keys = ON`.
* `down()` — `DROP TABLE IF EXISTS` for every
  `@Table`, in reverse order.

The user's function then just
`=> _$_InitialSchema();` — the codegen emits the
implementation. The migration is ready to be
added to the context's `migrations` list.

| Aspect | Value |
|---|---|
| Suffix | `.d_rocket_migration.g.dart` |
| Detects | top-level functions annotated with `@Migration` (annotation marker name `MigrationBase` in the analyzer lookup) |
| Per-class output | `class _$_<fnName> extends MigrationBase { ... }` |
| Cross-references | every `@Table` in the same library, in declaration order |
| Side effects | none beyond the generated `MigrationBase` subclass |

### `d_rocket_builder:record`

The default-suffix `record` builder. Walks every
class that `extends Record` (from
`package:d_rocket/d_rocket.dart`) — no annotation
required — and emits, per class:

* A `_<ClassName>Init` class whose constructor
  registers the field accessors with d_rocket's
  internal registry.
* A `final _$_<ClassName>Init` lazy top-level
  initializer.
* A public `void register<ClassName>Record()`
  function that forces evaluation of the
  initializer — called by the central
  `d_rocket_registry.g.dart` `initializeD()`.

```dart
class Author extends Record {
  final String name;
  final int age;
}
```

Becomes (per file):

```dart
class _$AuthorInit {
  _$AuthorInit() {
    final fields = <String, Object? Function(Author)>{
      fields['name'] = (a) => a.name;
      fields['age']  = (a) => a.age;
    };
    Record.register<Author>(fields);
  }
}

final _authorInit = _$AuthorInit();

void registerAuthorRecord() { _authorInit; }
```

| Aspect | Value |
|---|---|
| Suffix | `.g.dart` (the `source_gen` default — the only builder that uses it) |
| Detects | classes that `extends Record` (base class from `package:d_rocket`) |
| Per-class output | `_<ClassName>Init` + `_$<lcFirst>Init` + `register<ClassName>Record()` |
| Cross-references | none beyond the `Record.register<T>()` registry call |
| Side effects | none beyond the registry entry |

### `d_rocket_builder:record_registry`

A `LibraryBuilder` (not a `PartBuilder`).
Scans the consumer's `lib/**.dart` once,
collects every `extends Record` class AND every
`@Serializable` class AND every `@RestClient`
class AND every `@Table` class, AND every
`@WebSocketClient` / `@SseClient` abstract class,
and emits a single `lib/d_rocket_registry.g.dart`
with a public `initializeD()` function that calls
every `register<X>Record()`, every
`register<X>Serializer()`, every
`register<X>RestClient()`, every
`register<X>EntityMeta()`, and every
`register<X>Client` in one shot.

```dart
void initializeD() {
  registerAuthorRecord();
  registerBookRecord();
  registerOrderSerializer();
  registerOrdersApiRestClient();
  registerOrderEntityMeta();
  registerChatClient();
  // ...
}
```

The user calls `initializeD()` once in `main()`
and every d_rocket-managed class is wired up.

---

## Environment variables

Both CLIs read a few environment variables:

| Variable | Purpose |
|---|---|
| `D_ROCKET_MIGRATIONS_DIR` | Override the migration directory. |
| `D_ROCKET_DB_PATH` | Override the database path used by `doctor --db`. |
| `D_ROCKET_VERBOSE` | Enable verbose logging. |

`D_ROCKET_VERBOSE=1` prints every file the scaffolder
reads, every migration it finds, and every check it
runs. Useful for debugging.

---

## Programmatic access

The CLIs are thin wrappers over the framework's
programmatic API. If you want to roll your own
scaffolder, validator, or translator, the same
primitives are available:

```dart
import 'package:d_rocket/d_rocket.dart';

void main() {
  // Migration discovery
  final migrations = MigrationScanner.scan('lib/db/migrations/');
  print('Found ${migrations.length} migrations');

  // History verification
  final history = MigrationHistory.forDatabase(db);
  for (final m in migrations) {
    if (history.hasMismatch(m)) {
      print('${m.id} checksum mismatch');
    }
  }

  // Closure → Expr
  final expr = ClosureTranslator.translate(
    '(t) => t.x > 0',
    parameter: 't',
  );
  print(expr.toCode());
}
```

This is what the CLIs call under the hood. The
programmatic API is stable; the CLIs are convenience
wrappers.
