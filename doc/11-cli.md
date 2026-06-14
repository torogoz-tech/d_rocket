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
