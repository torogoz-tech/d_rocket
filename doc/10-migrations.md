# Migrations

Code-first schema management. Write a `Migration`
subclass; the runner tracks which ones have been
applied in a `_d_rocket_migrations` table. The
`MigrationStrategy` declarative list is paired with
optional imperative `onCreate` / `onUpgrade` /
`onDowngrade` callbacks for the cases that don't fit a
declarative migration.

This document covers both modes and the CLI scaffolder.

---

## Table of contents

- [The `Migration` base class](#the-migration-base-class)
- [The `MigrationStrategy`](#the-migrationstrategy)
- [`MigrationRunner`](#migrationrunner)
- [The history table](#the-history-table)
- [Mixing declarative and imperative](#mixing)
- [CLI scaffolder](#cli-scaffolder)
- [The doctor](#the-doctor)
- [Common patterns](#common-patterns)
- [API reference](#api-reference)

---

## The `MigrationBase` class

A migration is a class that extends `MigrationBase`:

```dart
import 'package:d_rocket/d_rocket.dart';

class M001CreateTodos extends MigrationBase {
  @override
  String get id => '001';

  @override
  int get version => 1;

  @override
  String get name => 'create_todos';

  @override
  void up(MigrationExecutor exec) {
    exec('''
      CREATE TABLE todos (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT    NOT NULL,
        done  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP TABLE todos');
  }
}
```

`MigrationExecutor` exposes the same `exec` you'd use
in a hand-written `onCreate` callback. The exec
function takes a SQL string and a list of positional
parameters:

```dart
exec('CREATE INDEX idx_todos_done ON todos (done)');
exec('UPDATE users SET active = ? WHERE last_seen < ?', [false, cutoff]);
```

For more complex operations, the executor has
helpers:

```dart
// Add a column.
exec.addColumn('orders', 'total', 'REAL NOT NULL DEFAULT 0.0');

// Rename a table.
exec.renameTable('orders', 'sales_orders');

// Drop a table if it exists.
exec.dropTableIfExists('legacy_users');
```

`MigrationBase` parameters:

| Member | Required | Purpose |
|---|---|---|
| `id` | yes | Stable string id. Convention: 3-digit, zero-padded (`'001'`, `'002'`, ...). |
| `version` | yes | Monotonic int. Defaults to `int.tryParse(id)` if `id` is numeric. |
| `name` | yes | Human-readable name for the doctor. |
| `up` | yes | Forward migration. |
| `down` | yes | Reverse migration. May be a no-op for irreversible migrations. |

The `id` and `version` are independent. The `id` is a
stable string (e.g. for commit messages); `version`
is the integer the runner uses to compute upgrades and
downgrades. You can use date-based ids:

```dart
class M2026_06_12_AddCustomerEmailIndex extends MigrationBase {
  @override
  String get id => '2026-06-12-001';

  @override
  int get version => 20260612001;

  @override
  String get name => 'add_customer_email_index';
  // ...
}
```

## Auto-migrations (1.2.0+)

As of **1.2.0** d_rocket ships a second migration
system that is the **recommended default for the
steady-state add-column / add-index / add-table
work**. Set `autoMigrate: true` on `Db.open` and
pass the list of codegen-emitted `EntityMeta`s:

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

The auto-migrator runs **after** the manual
`MigrationStrategy` (if one was provided). The
flow is:

1. Compute the new `SchemaSnapshot` from the
   entity list (deterministic JSON).
2. Read the last applied snapshot from the
   `d_rocket_schema_state` table (or `null` on
   fresh install).
3. Compute the diff.
4. Split into **safe** (auto-applied in a single
   transaction) and **unsafe** (reported, never
   auto-applied) operations.

| Operation | Severity | Auto-applies? |
|---|---|---|
| `CREATE TABLE` (new entity) | safe | ✅ |
| `CREATE INDEX` (new `@Index`) | safe | ✅ |
| `ADD COLUMN` nullable or with default | safe | ✅ |
| `ADD COLUMN` NOT NULL without default | unsafe | ❌ reported (SQLite cannot backfill) |
| `DROP TABLE` (entity removed) | unsafe | ❌ reported |
| `DROP COLUMN` (field removed) | unsafe | ❌ reported |
| `DROP INDEX` (`@Index` removed) | unsafe | ❌ reported |
| `MODIFY COLUMN` (type / nullability / default / FK change) | unsafe | ❌ reported (no ALTER COLUMN in SQLite) |
| Rename heuristic: drop + add of the same name with the same type | unsafe (suggestion) | ❌ reported (`ALTER TABLE ... RENAME COLUMN` for the user to confirm) |

Inspect the pending diff at any time:

```dart
final pending = await db.pendingSchemaDiff();
for (final diff in pending) {
  if (diff.severity == DiffSeverity.unsafe) {
    print('UNSAFE: ${diff.tableName}.${diff.columnName}');
    print('  reason: ${diff.reason}');
    print('  sql:    ${diff.sql}');
  }
}
```

### CLI: `migration check` (2.0.0 — Fase 11a)

The same diff is exposed via the CLI:

```bash
$ dart run d_rocket:migration check \
    --db app.db \
    --entities lib/db/entities.dart
```

The CLI requires a `lib/db/entities.dart` file that
exports your entity metas (one line per entity).
The CLI spawns a worker under `.d_rocket/` that
runs the diff against your SQLite DB and exits 1
if any unsafe diffs. Wire it into CI:

```yaml
# .github/workflows/ci.yml
- name: d_rocket schema check
  run: |
    dart run d_rocket:migration check \
      --db app.db \
      --entities lib/db/entities.dart
```

Exit codes: 0 on success (no unsafe diffs),
1 on unsafe diffs, 2 on usage error, 3 on worker
runtime error. See `doc/11-cli.md` for the full
reference.

The conservative default: when the auto-migrator
runs and finds unsafe diffs, the safe diffs are
applied but the new snapshot is **not** written
to `d_rocket_schema_state`. The unsafe diffs keep
showing up in `db.pendingSchemaDiff()` on every
reopen until the user handles them (typically by
writing a hand-rolled `MigrationBase` that
performs the unsafe change). This is intentional:
a pending unsafe diff is a louder signal than a
pending safe change, and we want the user to
handle the unsafe first.

The two migration systems coexist: hand-written
migrations run first, auto-migration runs after.
A project that started with hand-written
migrations can opt into auto-migration for the
steady-state add-column / add-index work without
rewriting the initial schema.

The auto-migrator never touches the
`_d_rocket_migrations` table — the hand-written
history and the auto-migration snapshot are
stored separately. Mixing the two does not
interfere.

## The `MigrationStrategy`

A `MigrationStrategy` is the declarative list of all
the migrations your app needs:

```dart
final db = await Db.open(
  path: 'app.db',
  strategy: MigrationStrategy(
    version: 4,
    migrations: [
      M001CreateTodos(),
      M002AddTodosDueDate(),
      M003CreateCustomers(),
      M004CreateOrders(),
    ],
  ),
);
```

The `version` field is the **target** version. The
runner compares it to the current version (stored in
`_d_rocket_migrations`) and either:

- Applies the upgrade subset (current < target).
- Rolls back the downgrade subset (current > target).
- Does nothing (current == target).

For a fresh install, the runner applies migrations
`[1..target]` in order. For an upgrade from version
2 to version 4, it applies `[3, 4]`. For a downgrade
from version 4 to version 2, it rolls back `[4, 3]`.

The runner wraps the whole batch in a single
transaction. If any migration fails, the entire batch
rolls back.

### Imperative callbacks

For the cases that don't fit a declarative migration
(seed data, environment-specific tables, etc.), use
the imperative callbacks:

```dart
MigrationStrategy(
  version: 4,
  migrations: [M001(), M002(), M003(), M004()],

  // Called on a fresh install BEFORE any migrations.
  onCreate: (db) async {
    await db.exec('CREATE TABLE settings (...)');
  },

  // Called on an upgrade AFTER the declarative
  // migrations have run.
  onUpgrade: (db, oldV, newV) async {
    if (oldV < 2) {
      await db.exec('UPDATE products SET legacy_id = id');
    }
  },

  // Called on a downgrade BEFORE the declarative
  // migrations are rolled back.
  onDowngrade: (db, oldV, newV) async {
    if (oldV >= 4 && newV < 4) {
      await db.exec('DELETE FROM audit_log WHERE created_at > ?', [someDate]);
    }
  },
);
```

The order of execution on an upgrade is:

1. `onUpgrade(db, oldV, newV)`
2. The declarative migration batch
3. (none)

The order on a downgrade is:

1. `onDowngrade(db, oldV, newV)`
2. The declarative migration batch (rolled back)
3. (none)

The order on a fresh install is:

1. `onCreate(db)`
2. The declarative migration batch
3. (none)

## `MigrationRunner`

For lower-level control, you can use `MigrationRunner`
directly:

```dart
final runner = MigrationRunner();

runner.run(
  db,
  migrations: [M001CreateTodos(), M002AddTodosDueDate()],
  targetVersion: 2,
);
```

The runner is what the framework uses internally when
you pass a `MigrationStrategy` to `Db.open`. You
rarely need it directly.

## The history table

The runner persists the migration history in a
`_d_rocket_migrations` table:

```sql
CREATE TABLE _d_rocket_migrations (
  id          TEXT    PRIMARY KEY,  -- '001', '002', ...
  version     INTEGER NOT NULL,
  name        TEXT    NOT NULL,
  applied_at  TEXT    NOT NULL,     -- ISO-8601
  checksum    TEXT    NOT NULL      -- SHA-256 of the SQL body
);
```

The `checksum` column lets the runner detect when a
migration has been edited after it was applied. If the
checksum changes, the runner throws a
`MigrationChecksumMismatchException` and refuses to
proceed. This is intentional: a migration should be
immutable once applied.

If you need to edit a migration that hasn't been
deployed yet (you're still in development), just
delete the database and re-run. For production, the
recommended fix is to add a new migration that
performs the desired change.

## Mixing declarative and imperative

A common pattern is to keep the schema in declarative
migrations and use the imperative callbacks for
seed data:

```dart
MigrationStrategy(
  version: 4,
  migrations: [
    M001CreateTodos(),
    M002AddTodosDueDate(),
    M003CreateCustomers(),
    M004CreateOrders(),
  ],

  // Run on a fresh install. Useful for seed data
  // that the schema doesn't express.
  onCreate: (db) async {
    await db.exec(
      "INSERT INTO settings (key, value) VALUES ('currency', 'USD')",
    );
  },
);
```

The `onCreate` callback is also the right place to
register a user, set up an admin account, or do any
other one-time work that isn't a schema change.

## CLI scaffolder

`dart run bin/migration.dart add <name>` scaffolds
a new migration. As of 1.2.1 the CLI is **minimal**
— it emits a skeleton with the right `id` and
`class` names and pre-filled `// TODO`
bodies, but the generated SQL is not auto-populated
from the entity diff. A 1.3.0 candidate (CLI
scaffolder with EF Core parity) is documented in
[ROADMAP.md](ROADMAP.md#13-candidates).

```bash
$ dart run bin/migration.dart add create_inventory_table
✅ Created lib/db/migrations/M005_create_inventory_table.dart
   id: 005, class: M005CreateInventoryTable
```

The scaffolder picks the next id by scanning the
existing migrations. The default location is
`lib/db/migrations/`. To override, set
`D_ROCKET_MIGRATIONS_DIR`:

```bash
$ D_ROCKET_MIGRATIONS_DIR=lib/database/migrations \
    dart run d_rocket:migration add create_inventory_table
```

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

## The doctor

`d_rocket:migration doctor` validates the
migration history:

```bash
$ dart run d_rocket:migration doctor
✅ Migration history is contiguous (5 migrations).
```

The doctor checks for:
- **Gaps** in the sequence (e.g. `001`, `003` but no `002`).
- **Duplicate ids** or versions.
- **Checksum mismatches** between the source and the
  applied history (requires a database connection).
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

## Common patterns

### Adding a column

```dart
class M005AddCustomerEmailIndex extends Migration {
  // ...
  @override
  void up(MigrationExecutor exec) {
    exec.addIndex('customers', 'idx_email', ['email'], unique: true);
  }
  @override
  void down(MigrationExecutor exec) {
    exec.dropIndex('idx_email');
  }
}
```

### Renaming a column

SQLite doesn't support `ALTER TABLE ... RENAME COLUMN`
on older versions. The portable pattern is to add a
new column, copy the data, and drop the old one:

```dart
@override
void up(MigrationExecutor exec) {
  exec.addColumn('users', 'display_name', 'TEXT');
  exec('UPDATE users SET display_name = name');
  // SQLite 3.25+ supports RENAME COLUMN. Use it if available.
  try {
    exec('ALTER TABLE users RENAME COLUMN name TO name_legacy');
  } catch (_) {
    // Fallback: leave both columns; the codegen will
    // deprecate `name` in a future migration.
  }
}
```

### Seeding initial data

```dart
@override
void up(MigrationExecutor exec) {
  exec('''
    INSERT INTO roles (id, name) VALUES
      (1, 'admin'),
      (2, 'user'),
      (3, 'guest')
  ''');
}
```

For complex seed data, read it from a JSON file:

```dart
@override
Future<void> up(MigrationExecutor exec) async {
  final seed = json.decode(await File('seeds/countries.json').readAsString());
  for (final row in seed) {
    exec('INSERT INTO countries (code, name) VALUES (?, ?)',
         [row['code'], row['name']]);
  }
}
```

### Multi-database migrations

If you have multiple databases (one per tenant, e.g.),
the migration runner takes a `Db` argument and
runs against that db. Use a separate `MigrationStrategy`
per database:

```dart
for (final tenant in tenants) {
  final db = await Db.open(
    path: 'tenants/${tenant.id}.db',
    strategy: MigrationStrategy(...),
  );
}
```

The runner doesn't share state between databases —
each gets its own `_d_rocket_migrations` table.

## API reference

### `MigrationBase`

Abstract base class. Members: `id`, `version`, `name`,
`up(exec)`, `down(exec)`.

### `MigrationExecutor`

Provided to `up` / `down`. Methods: `exec(sql, params)`,
`addColumn`, `renameColumn`, `dropColumn`, `addIndex`,
`dropIndex`, `renameTable`, `dropTableIfExists`.

### `MigrationStrategy`

Top-level migration config. Fields: `version`,
`migrations`, `onCreate`, `onUpgrade`, `onDowngrade`.

### `MigrationRunner`

Lower-level runner. Methods: `run(db, migrations, targetVersion)`,
`currentVersion(db)`, `pendingMigrations(db, strategy)`.

### `MigrationChecksumMismatchException`

Thrown when a migration's checksum doesn't match the
one in the history table. Refusing to proceed is
intentional; migrations are immutable once applied.

### `MigrationHistory`

The state of applied migrations. Inspectable via
`runner.history(db)` or `db.migrationHistory`.
