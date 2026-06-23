# Layer 4 — ORM (engine-agnostic)

The ORM provides annotation-driven entity declaration,
change-tracked mutations, and LINQ push-down to the
engine. The user declares `@Table` classes, the codegen
emits a `fromRow` factory and an `EntityMeta` for each,
and the runtime provides a `DbContext` base
class that the user subclasses to wire the `DbSet<T>`
getters.

The ORM is **engine-agnostic** — it talks to any
`AsyncQueryProvider`. In 2.0.0 three engines ship
in separate packages:

- `d_rocket_engine_sqlite` — `package:sqlite3` (file
  or `sqlite::memory:`). Has **both** sync and async
  LINQ.
- `d_rocket_engine_postgres` — `package:postgres`
  (wire protocol, pure Dart, no FFI). Async-only LINQ.
- `d_rocket_engine_web` — IndexedDB via `package:idb_shim`
  (browser). Async-only LINQ.

Pick the engine that matches the target platform, add
its package to your `pubspec.yaml`, and call its
registration helper (`dRocketSqlite()`,
`dRocketPostgres()`, or `dRocketWeb()`) once at app
startup before any `Db.open` / `PgDb.open` / `WebDb.open`
call.

> **Note (1.x → 2.0):** the SQLite provider used to
> ship inside `d_rocket`. In 2.0.0 the ORM core was
> decoupled from the engine and the SQLite provider
> moved to a separate `d_rocket_engine_sqlite` package.

---

## Table of contents

- [Defining an entity](#defining-an-entity)
- [Defining a `DbContext` subclass](#defining-a-rocketdbcontext-subclass)
- [`@Table` parameters](#rockettable-parameters)
- [`@PrimaryKey` parameters](#primarykey-parameters)
- [`@Column` parameters](#column-parameters)
- [`@ForeignKey` parameters](#foreignkey-parameters)
- [`@Embedded` parameters](#embedded-parameters)
- [`@Index` parameters](#index-parameters)
- [Navigation properties](#navigation-properties)
- [`DbSet<T>` API](#dbsett-api)
- [`ChangeTracker`](#changetracker)
- [Supported types](#supported-types)
- [API reference](#api-reference)

---

## Defining an entity

A `@Table` is a class that extends `Record` (the
framework's typed-marker base class) — or implements
`RecordLike` directly (for classes that can't extend
`Record` because of an existing superclass):

```dart
import 'package:d_rocket/d_rocket.dart';

@Table()
class Order extends Record {
  @PrimaryKey()
  final int id;

  @Column(name: 'customer_id')
  @ForeignKey(table: 'customers', column: 'id')
  final int customerId;

  @Column()
  final String status;

  @Column(name: 'placed_at')
  final DateTime placedAt;

  Order({
    this.id = 0,
    required this.customerId,
    required this.status,
    required this.placedAt,
  });
}
```

If `@Table()` is called with no arguments, the
codegen derives the table name from the class name
(snake_case). With `name: 'sales_orders'`, the
explicit name is used.

The class must `extends Record` (or implement
`RecordLike` directly) so the ORM can read field
values via the `readField(name)` method.

### Field rules

Fields that are not annotated as `@PrimaryKey`,
`@Column`, `@ForeignKey`, or `@Embedded` are
**ignored by the ORM**. This keeps the model free to
have computed fields, transient state, or methods
without polluting the table DDL.

## Defining a `DbContext` subclass

The user writes a context that wires the entity
classes to `DbSet<T>` getters:

```dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';

class MyDbContext extends DbContext {
  // The codegen-emitted EntityMeta lookup for each
  // @Table class. Subclass-friendly.
  late final DbSet<Order> orders = dbSet<Order>(entityMetaFor);
  late final DbSet<Customer> customers =
      dbSet<Customer>(entityMetaFor);

  // Provider hook. The user overrides this to expose
  // the underlying storage. The base class wires the
  // provider into every `DbSet<T>` automatically.
  @override
  AsyncQueryProvider? get asyncProvider => _provider;
  final AsyncQueryProvider? _provider;

  MyDbContext(this._provider);
}
```

A real subclass with a SQLite database:

```dart
class MySqliteContext extends DbContext {
  MySqliteContext(this.provider);
  final SqliteQueryProvider provider;

  late final DbSet<Order> orders = dbSet<Order>(entityMetaFor);
  late final DbSet<Customer> customers =
      dbSet<Customer>(entityMetaFor);

  @override
  AsyncQueryProvider? get asyncProvider => provider;

  @override
  int saveChanges() {
    // Optional: wrap the whole batch in a transaction.
    return super.saveChanges();
  }
}

// At startup:
final ctx = MySqliteContext(
  SqliteQueryProvider.fromPath('app.db'),
);
```

The context owns:
- one `ChangeTracker` (shared across every `DbSet<T>`)
- a set of `DbSet<T>` instances (one per `@Table` class)
- a connection to the underlying storage (a SQLite database in the MVP)

`dbSet<T>(metaAccessor)` lazily constructs a `DbSet<T>`
on the first call and caches it. Subsequent calls
return the cached instance.

## `@Table` parameters

```dart
const Table({
  this.name,
  this.discriminator,
  this.inheritance = InheritanceStrategy.none,
  this.children,
  this.isAbstract = false,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `name` | `null` | SQL table name. If `null`, derived from the class name (snake_case). |
| `discriminator` | `null` | TPH discriminator value. Set on the **child** entity with the discriminator string (e.g. `'dog'`). |
| `inheritance` | `InheritanceStrategy.none` | One of: `none`, `tph` (table-per-hierarchy), `tpc` (table-per-concrete). |
| `children` | `null` | TPH children map (discriminator value → Dart class name). Only meaningful on a TPH root. |
| `isAbstract` | `false` | Marks this entity as a TPC root that owns no table. The leaf entities own the actual tables. |

### Convenience constructors

```dart
const Table.tph({String? name, Map<String, String>? children})
const Table.tpc({String? name})
```

`Table.tph(name: 'animals', children: {'dog': 'Dog', 'cat': 'Cat'})`
is shorthand for `Table(inheritance: InheritanceStrategy.tph,
name: 'animals', children: {...})`. Same for `.tpc`.

## `@PrimaryKey` parameters

```dart
const PrimaryKey({this.autoIncrement = true});
```

| Parameter | Default | Purpose |
|---|---|---|
| `autoIncrement` | `true` | Whether the underlying `INTEGER PRIMARY KEY` should auto-increment. The default `true` emits `INTEGER PRIMARY KEY AUTOINCREMENT` in the DDL. |

Exactly one field per entity class must carry this
annotation. The codegen uses `autoIncrement` to
decide whether to back-propagate the DB-assigned PK
to the in-memory entity after an `INSERT`.

## `@Column` parameters

```dart
const Column({
  this.name,
  this.nullable = false,
  this.isForeignKey = false,
  this.defaultValue,
  this.discriminator = false,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `name` | `null` | SQL column name. If `null`, derived from the field name (snake_case). |
| `nullable` | `false` | Whether the column accepts `NULL`. The DDL respects this. |
| `isForeignKey` | `false` | Whether this column is a foreign key. Defaults to `false`; convenience wrappers like `@ForeignKey` set this. |
| `defaultValue` | `null` | Optional default value. The codegen embeds the literal into the `CREATE TABLE` statement. |
| `discriminator` | `false` | Marks this column as the TPH discriminator. Exactly one column per TPH root should set this to `true`. |

## `@ForeignKey` parameters

```dart
const ForeignKey({
  super.name,
  super.nullable,
  super.defaultValue,
  required this.table,
  required this.column,
}) : super(isForeignKey: true);
```

`@ForeignKey` extends `@Column` and adds the target
reference. The codegen surfaces the reference in
`ColumnMeta` and `EntityMeta` but does **not** emit
`FOREIGN KEY ... REFERENCES ...` in the DDL (yet).

| Parameter | Required | Purpose |
|---|---|---|
| `table` | yes | Target table name (snake_case, e.g. `'customers'`). |
| `column` | yes | Target column name (e.g. `'id'`). |
| `name` | no | Override the column name on this side. |
| `nullable` | no | Whether the FK is nullable. |
| `defaultValue` | no | Optional default. |

## `@Embedded` parameters

```dart
const Embedded({this.prefix});
```

Marks a field as an embedded value object (EF Core's
`OwnsOne` / `ComplexProperty` pattern). The fields
of the embedded type are **flattened** into the
parent table — they don't get their own table and
they don't carry an FK.

| Parameter | Default | Purpose |
|---|---|---|
| `prefix` | `null` | Optional prefix to apply to the embedded column names. If `null`, columns are emitted as-is (e.g. `street`, `city`). If non-null (e.g. `'addr'`), columns are emitted as `addr_street`, `addr_city`. |

## `@Index` parameters

```dart
const Index({this.unique = false, this.name});
```

Marks a field (or set of fields, in a future
iteration) for indexing. As of **1.1.1** the
codegen emits a `CREATE INDEX` statement in the
auto-migrator's CREATE TABLE output and in the
`MigrationGenerator` hand-rolled migration
template; the `autoMigrate: true` path on
`Db.open(entityMetas: ...)` creates the index as
part of the fresh-install diff.

| Parameter | Default | Purpose |
|---|---|---|
| `unique` | `false` | Whether the index is unique. |
| `name` | `null` | Optional index name. If `null`, the codegen derives `<table>_<column>_idx` (or `_unq` for unique indexes). |

The DDL is emitted as `CREATE [UNIQUE] INDEX
IF NOT EXISTS <name> ON <table>(<column>)` and
is non-destructive (the `IF NOT EXISTS` clause
makes it safe to re-run on every open).

## Navigation properties

There is **no `@BelongsTo` or `@HasMany` annotation**.
Navigation properties are computed by the codegen
from `@ForeignKey` fields. The codegen:

1. Inspects every `@ForeignKey` column on the entity.
2. Derives the target entity (via the `table` /
   `column` reference).
3. Looks for an inverse FK on the target entity
   (a `@ForeignKey` pointing back to this one).
4. If an inverse FK exists, the navigation is
   `1:many` (a `List<Target>`). If not, the
   navigation is `1:1` (a `Target?`).
5. Emits a `NavigationMeta` per navigation, plus a
   `customer` getter on the entity (for 1:1) or
   `lineItems` getter (for 1:many).

The runtime uses the `NavigationMeta` to:

- Generate the navigation getter (codegen).
- Translate `o.customer.name` in a closure to a
  JOIN (SQL provider).
- Implement `.include_<TNav>()` for eager loading.
- Detect N+1 patterns (lint rule).

## `DbSet<T>` API

`DbSet<T>` is a typed, queryable collection of `T`
entities backed by a single SQL table. The user
gets one per `@Table` class via the
`dbSet<T>(...)` method on their `DbContext`
subclass.

### Sync mutating methods (stage in `ChangeTracker`)

| Method | Purpose |
|---|---|
| `add(T entity)` | Stage an insert. The `INSERT` SQL runs on the next `saveChanges`. |
| `addRange(Iterable<T>)` | Stage multiple inserts in order. |
| `remove(T entity)` | Stage a deletion. The `DELETE` SQL runs on the next `saveChanges`. |
| `markModified(T entity)` | Stage an update. (Note: not `updateWhere(predicate, fn)` — the user mutates the entity and calls `markModified` to stage it.) |
| `markDeleted(T entity)` | Alias for `remove(T)`. EF Core nomenclature. |
| `markUnchanged(T entity)` | Stage as Unchanged. Useful after a manual flush that the runtime didn't know about. |
| `clearLocalChanges()` | Drop every tracked entry for `T`. |

The mutating methods do **not** run SQL. They stage
in the `ChangeTracker`. The SQL runs on the next
`DbContext.saveChanges()`.

### Sync read methods (run SQL immediately)

| Method | Returns | Purpose |
|---|---|---|
| `toList()` | `List<T>` | All rows. Throws `UnsupportedError` if `EntityMeta.fromRow` is missing. |
| `findById(Object id, {include, joins})` | `T?` | Lookup by PK. `include` is a list of post-load callbacks; `joins` is a list of `IncludeOne` / `IncludeMany` for declarative single-SQL eager-loading. |
| `firstBy({column, value})` | `T?` | First entity whose `column` equals `value`. Throws `StateError` if `column` is not declared. |
| `allBy({column, value})` | `List<T>` | Every entity whose `column` equals `value`. |

### Async read methods (require `AsyncQueryProvider`)

| Method | Returns | Purpose |
|---|---|---|
| `toListAsync_()` | `Future<List<T>>` | Async counterpart of `toList()`. Throws `StateError` if no `AsyncQueryProvider` is attached. |
| `findByIdAsync(Object id, {include, joins})` | `Future<T?>` | Async counterpart of `findById`. |
| `firstByAsync({column, value})` | `Future<T?>` | Async counterpart of `firstBy`. |
| `allByAsync({column, value})` | `Future<List<T>>` | Async counterpart of `allBy`. |
| `toListWithIncludesAsync_()` | `Future<List<T>>` | Like `toListAsync_` but also applies any pending `include_<TNav>()` calls. Returns the same list with the navigation properties populated. |

### Eager loading

Two patterns:

**Callback-based `include`** — runs N+1 queries:

```dart
final book = ctx.books.findById(1, include: [
  (Book b) => b.author = ctx.customers.firstBy(
        column: 'id', value: b.customerId,
      ),
  (Book b) => b.sales = ctx.sales.allBy(
        column: 'book_id', value: b.id,
      ),
]);
```

**Declarative `joins`** — single SQL with `LEFT JOIN`s:

```dart
final book = ctx.books.findById(1, joins: [
  IncludeOne<Book, Customer>(
    navigationName: 'author',
    relatedTable: 'customers',
    fkColumnOnT: 'customer_id',
  ),
  IncludeMany<Book, Sale>(
    navigationName: 'sales',
    relatedTable: 'sales',
    inverseFkColumn: 'book_id',
  ),
]);
```

The joins form is faster (one SQL statement) and
populates the `NavigationRegistry` for the included
navigations.

**Chainable `include_<TNav>()`** — applies via
`toListWithIncludesAsync_()`:

```dart
final books = await ctx
    .books
    .include_<Customer>()
    .include_<Sale>()
    .toListWithIncludesAsync_();
```

The codegen emits a typed wrapper per navigation,
so `.include_<Customer>` is shorthand for the
string-based `include_<TNav>(name, targetMeta)`.
The generic `<TNav>` is for documentation; the
runtime doesn't use it.

### Bulk operations

| Method | Returns | Purpose |
|---|---|---|
| `executeBulkUpdate({setters, where, whereBinds})` | `Future<int>` | Run a single `UPDATE <table> SET ... [WHERE ...]`. `setters` is a `Map<String, Object?>` of column → value. Column names are raw SQL. |
| `executeBulkDelete({where, whereBinds})` | `Future<int>` | Run a single `DELETE FROM <table> [WHERE ...]`. |

### Reactive queries

| Method | Returns | Purpose |
|---|---|---|
| `watch({pollInterval})` | `Stream<List<T>>` | Emits the current rows on every `pollInterval` tick AND on every `ChangeTracker.changes` event. Default `pollInterval` is 1 second. Designed for Flutter's `StreamBuilder`. |

The watch stream is a combined stream: the generator
listens to BOTH the periodic poll AND the
change-tracker events. On EITHER firing, it
re-queries the table and yields.

### Provider attachment

```dart
ctx.books.attachAsyncProvider(myProvider);
ctx.books.attach<MyProvider>(myOtherProvider);
ctx.books.get<MyProvider>();          // → MyProvider?
ctx.books.asyncProvider;              // → AsyncQueryProvider?
ctx.books.changeTracker;              // → ChangeTracker
ctx.books.meta;                       // → EntityMeta
```

`attach<P>(provider)` is the generic provider
attachment hook. Provider packages use it to wire
their own backends (e.g. `d_rocket_provider_sqlite`
calls `dbSet.attach<SqliteQueryProvider>(p)`).

## `ChangeTracker`

The `ChangeTracker` is the in-memory bookkeeping
for staged mutations. One per `DbContext`.

| Property / method | Purpose |
|---|---|
| `changeTracker.length` | Total tracked entries. |
| `changeTracker.entries` | Snapshot of every tracked entry (in insertion order). |
| `changeTracker.changes` | Broadcast `Stream<ChangeEvent>` for reactive queries. |
| `changeTracker.track(entity, state)` | Add or update a tracked entry. (Internal — the user calls `DbSet.add` / `markModified`.) |
| `changeTracker.untrack(pk)` | Remove an entry by PK. |
| `changeTracker.clear()` | Drop all entries. |
| `changeTracker.untrackAll()` | Drop all entries, emit a `cleared` event. |

### `ChangeEvent`

Broadcast on every state transition:

```dart
class ChangeEvent {
  final ChangeEventType type;
  final Object? entity;
  final TrackedEntry? trackedEntry;
}

enum ChangeEventType {
  added,      // entity was added to the tracker
  modified,   // entity's state was changed to modified
  removed,    // entity was marked for deletion
  saved,      // entity's state was reset to unchanged
  cleared,    // entire tracker was cleared
}
```

### `TrackedEntry`

A single tracked row:

```dart
class TrackedEntry {
  final Object entity;
  final EntityState state;
  final Map<String, Object?> originalValues;  // per-column "before" snapshot
  final TrackedKey pk;
}

enum EntityState {
  unchanged,
  added,
  modified,
  removed,
  detached,
}
```

## Supported types

The codegen handles the following Dart types in
`@Column` fields:

| Dart type | SQL type | Notes |
|---|---|---|
| `int` | `INTEGER` | Native int. |
| `double` | `REAL` | Native double. |
| `num` | `NUMERIC` | Affinity-typed. |
| `String` | `TEXT` | UTF-8. |
| `bool` | `INTEGER` | 0/1. |
| `DateTime` | `TEXT` | ISO-8601 string. |
| `Uint8List` | `BLOB` | Raw bytes. |
| An `@Serializable` class | `TEXT` (JSON) | Stored as a JSON object. |
| An enum | `TEXT` | The `name`. |
| An `@Embedded` class | flattened | Multiple columns on the parent table. |

## API reference

### `@Table(...)` / `@Table.tph(...)` / `@Table.tpc(...)`

Class annotation. See parameters above.

### `@PrimaryKey({autoIncrement})`

Field annotation. Exactly one per entity class.

### `@Column({name, nullable, isForeignKey, defaultValue, discriminator})`

Field annotation. Most fields are `@Column`.

### `@ForeignKey({name, nullable, defaultValue, table, column})`

Field annotation. Extends `@Column` with a target
reference. `table` and `column` are required.

### `@Embedded({prefix})`

Field annotation. Marks a field as a value object
whose fields are flattened into the parent table.

### `@Index({unique, name})`

Field annotation. Metadata-only in the MVP (no DDL
emitted).

### `DbContext`

Abstract base class. The user subclasses it and adds
`DbSet<T> get t` getters. Provides:

| Member | Purpose |
|---|---|
| `changeTracker` | The shared `ChangeTracker`. |
| `dbSet<T>(metaAccessor, {hierarchy})` | Lazily-constructs a `DbSet<T>`. |
| `entityMetaFor<T>()` | Looks up the codegen-emitted `EntityMeta` from the central `EntityRegistry`. |
| `asyncProvider` (getter) | Override to expose the underlying storage. |
| `createSaveChangesTransaction` (getter) | Override to wrap `saveChanges` in a transaction. |
| `saveChanges()` | Flush every staged INSERT / UPDATE / DELETE. Returns rows affected. |
| `saveChangesAsync()` | Async counterpart. |

### `DbSet<T>`

See [DbSet API](#dbsett-api) above.

### `ChangeTracker`, `ChangeEvent`, `ChangeEventType`, `TrackedEntry`, `EntityState`

See [ChangeTracker](#changetracker) above.

### `EntityMeta`, `ColumnMeta`, `NavigationMeta`, `EmbeddedMeta`

Codegen-emitted metadata. Read at runtime; not
constructed by the user.
