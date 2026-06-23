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
- [Embedded value objects (`@Embedded` + `EmbeddedMeta`)](#embedded-value-objects-embedded--embeddedmeta)
- [`@Index` parameters](#index-parameters)
- [Navigation properties](#navigation-properties)
- [`DbSet<T>` API](#dbsett-api)
- [`DbSet<T>` attach system](#dbsett-attach-system)
- [`DbSet<T>` tracking and PK helpers](#dbsett-tracking-and-pk-helpers)
- [Bulk operations](#bulk-operations-on-dbsett)
- [ChangeTracker](#changetracker)
- [Supported types](#supported-types)
- [Inheritance (`InheritanceStrategy`)](#inheritance-inheritancestrategy)
- [Foreign-key `ON DELETE` actions (`OnDeleteAction`)](#foreign-key-on-delete-actions-ondeleteaction)
- [Code-first migrations (`@Migration`, `MigrationBase`)](#code-first-migrations-migration-migrationbase)
- [`MigrationStrategy` (declarative + imperative)](#migrationstrategy-declarative--imperative)
- [`AppliedMigration`](#appliedmigration)
- [`DbInterceptor` + `InterceptorRegistry`](#dbinterceptor--interceptorregistry)
- [Eager loading (`IncludeRelation` / `IncludeOne` / `IncludeMany`)](#eager-loading-includerelation--includeone--includemany)
- [Navigation infrastructure (`NavigationPopulator` + `NavigationRegistry` + `DbSetInclude`)](#navigation-infrastructure-navigationpopulator--navigationregistry--dbsetinclude)
- [Metadata types (`EntityMeta`, `ColumnMeta`, `NavigationMeta`)](#metadata-types-entitymeta-columnmeta-navigationmeta)
- [`EntityRegistry`](#entityregistry)
- [Error hierarchy (`DatabaseException`)](#error-hierarchy-databaseexception)
- [SQL log redaction (`redactPragmaKey`)](#sql-log-redaction-redactpragmey)
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
`OwnsOne` / `ComplexProperty` pattern). The fields of
the embedded type are **flattened** into the parent
table — they don't get their own table and they
don't carry an FK.

| Parameter | Default | Purpose |
|---|---|---|
| `prefix` | `null` | Optional prefix to apply to the embedded column names. If `null`, columns are emitted as-is (e.g. `street`, `city`). If non-null (e.g. `'addr'`), columns are emitted as `addr_street`, `addr_city`. |

See [Embedded value objects](#embedded-value-objects-embedded--embeddedmeta)
for the codegen-emitted `EmbeddedMeta` that drives
the flatten + row round-trip.

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

See [Bulk operations on `DbSet<T>`](#bulk-operations-on-dbsett)
for the engine-level `BulkOpsAsync` extension that
backs these methods, and the full
before/after example.

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

See [`DbSet<T>` attach system](#dbsett-attach-system)
for the full surface (`attach`, `get`,
`attachAsyncProvider`, `attachInterceptors`).

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
constructed by the user. See [Metadata
types](#metadata-types-entitymeta-columnmeta-navigationmeta)
for the full field-by-field reference.

---

## Embedded value objects (`@Embedded` + `EmbeddedMeta`)

`@Embedded` marks a field as a value object whose
fields are **flattened** into the parent table — no
own table, no FK. The codegen emits an `EmbeddedMeta`
per `@Embedded` field; the runtime reads it to
materialise rows back into the embedded object.

```dart
class Address {
  final String street;
  final String city;
  const Address({required this.street, required this.city});
}

@Table()
class Customer extends Record {
  @PrimaryKey()
  final int id;

  @Column()
  final String name;

  @Embedded()
  final Address address; // flattened → `street`, `city`

  Customer({this.id = 0, required this.name, required this.address});
}
```

The DDL is `CREATE TABLE customers (id INTEGER
PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, street
TEXT NOT NULL, city TEXT NOT NULL)` — no `address`
column and no FK. The codegen populates the
`EmbeddedMeta` so `toList()` knows to read the
flattened columns back into an `Address` instance
and assign it to `customer.address`.

With `prefix`:

```dart
@Embedded(prefix: 'addr')
final Address address;
// → addr_street, addr_city
```

### `EmbeddedMeta` reference

| Field | Purpose |
|---|---|
| `name` | The field name on the parent (e.g. `'address'`). |
| `dartType` | Runtime type of the embedded object (e.g. `Address`). |
| `columns` | The flattened `ColumnMeta` list. |
| `prefix` | Optional SQL-column prefix; `null` means as-is. |
| `fromRow` | Codegen factory that builds the embedded object from a row map. |
| `get` | Codegen getter that extracts the embedded object from a parent instance. |
| `set` | Codegen setter that writes the embedded object onto a parent instance. |
| `sqlName(c)` | Returns `c.sqlName` (or `'<prefix>_${c.sqlName}'` when prefixed). |

MVP scope: only single-instance embedding (`OwnsOne`).
Collections (`OwnsMany`) are not yet supported.

---

## `DbSet<T>` attach system

The core `DbSet<T>` is **provider-agnostic**. Provider
packages attach their own backends through a small
generic hook (`attach<P>` + `get<P>`), plus two
specialised hooks (`attachAsyncProvider` and
`attachInterceptors`).

```dart
// (provider-agnostic): wire the async I/O backend.
ctx.books.attachAsyncProvider(sqliteProvider);

// (provider-specific): wire an extra backend through
// the generic typed hook.
ctx.books.attach<SqliteQueryProvider>(sqliteProvider);

// (Phase 3.7): wire the interceptor chain. The
// surrounding DbContext does this automatically when
// you go through dbSet<T>(), so most user code never
// needs to call it.
ctx.books.attachInterceptors(ctx.interceptors);
```

| Method | Returns | Purpose |
|---|---|---|
| `attach<P>(P provider)` | `DbSet<T>` | Generic typed attachment, keyed by `Type`. Idempotent; returns `this` for chaining. Provider packages use it to wire their backend (e.g. `dbSet.attach<SqliteQueryProvider>(p)`). |
| `get<P>()` | `P?` | Looks up an attached provider by type. Returns `null` if no provider of that type is attached. Provider-specific extensions use this to retrieve what they put in via `attach`. |
| `attachAsyncProvider(AsyncQueryProvider provider)` | `DbSet<T>` | Attaches the async backend that powers `*Async_` read methods and the async write path. Idempotent. |
| `attachInterceptors(InterceptorRegistry interceptors)` | `DbSet<T>` | Wires the `InterceptorRegistry` from the surrounding `DbContext`. The `dbSet<T>()` constructor on `DbContext` calls this automatically, so most user code never invokes it directly. |
| `asyncProvider` (getter) | `AsyncQueryProvider?` | Public read-only accessor for the async provider. Provider packages read this to avoid forcing the user to pass the backend twice. |
| `changeTracker` (getter) | `ChangeTracker` | The shared tracker owned by the surrounding `DbContext`. |

The `_attachments` map is internal. `attach` is the
only way to populate it; `get` is the only way to
read it. Provider extensions are the canonical
consumers of the `attach<P>` / `get<P>` pair.

---

## `DbSet<T>` tracking and PK helpers

These methods are mostly internal to the
`saveChanges` flow, but are exposed for provider
extensions and for users writing custom pipelines
(e.g. a manual sync loop, a test fixture, a
hand-rolled export).

| Method | Returns | Purpose |
|---|---|---|
| `clearLocalChanges()` | `void` | Drops every tracked entry whose entity is of type `T`. The next `saveChanges` will be a no-op for `T`. Useful for tests and "forget what I did" patterns. |
| `lastInsertedPk()` | `int?` | Returns the `lastInsertRowId` of the most recent INSERT on this `DbSet`. Used by `saveChanges` to back-propagate the DB-assigned PK per entity (a previous bug read it after the whole loop and all entities ended up with the last PK). Returns `null` if the provider does not support `lastInsertRowId` (e.g. the in-memory test fixture). |
| `lastInsertedPkAsync()` | `Future<int?>` | Async counterpart. Throws `StateError` if no `AsyncQueryProvider` is attached. |
| `lastInsertRowId()` | `int` | Raw accessor for the provider's `lastInsertRowId`. Unlike `lastInsertedPk`, this throws if the provider does not implement it. |
| `backPropagatePk(T entity)` | `void` | Calls the codegen-supplied `EntityMeta.setId` with the most recent `lastInsertRowId`. No-op if the PK is not auto-increment or the codegen did not emit a `setId` hook (a missing hook usually means a hand-rolled test fixture). The codegen throws at build time if the PK field is `final`. |
| `insertOneWith(T entity, MigrationExecutor exec)` | `int?` | Variant of `insertOne` that runs the SQL through a `MigrationExecutor` (transaction-scoped). Used by `DbContext.saveChanges` when `createSaveChangesTransaction` is set. Does NOT back-propagate the PK — that's the caller's job, after commit. |
| `updateOneWith(entity, originalValues, exec)` | `int` | Transactional counterpart of `updateOne`. Returns 1; the transaction's commit is what makes the change durable. |
| `deleteOneWith(T entity, MigrationExecutor exec)` | `int` | Transactional counterpart of `deleteOne`. Returns 1; same commit semantics. |

> **Why the `With` variants exist.** The sync
> `saveChanges` path takes the `MigrationExecutor`
> from `createSaveChangesTransaction` (so the whole
> batch is atomic); the async `saveChangesAsync`
> path takes the `AsyncQueryProvider`'s
> `executeAsync` directly. The two paths share the
> SQL-builder logic; only the executor differs.

---

## Bulk operations on `DbSet<T>`

The `executeBulkUpdate` / `executeBulkDelete` methods
on `DbSet<T>` are thin wrappers around the
`BulkOpsAsync` extension on `AsyncQueryProvider`.
The extension is the lower-level surface and is
the one used by the LINQ compiler for
`ExecuteUpdateAsync` / `ExecuteDeleteAsync`
push-down.

### Before / after

```dart
// Before: 1 + N round-trips.
final List<Book> books = await provider.selectAsync(
  'SELECT * FROM books WHERE stock < ?',
  <Object?>[10],
);
for (final Book b in books) {
  await provider.executeAsync(
    'UPDATE books SET low_stock = ? WHERE id = ?',
    <Object?>[true, b.id],
  );
}

// After: 1 round-trip total.
await ctx.books.executeBulkUpdate(
  setters: <String, Object?>{'low_stock': true},
  where: 'stock < ?',
  whereBinds: <Object?>[10],
);
```

The `setters` map values are bound as positional
`?` parameters — user input is safe from SQL
injection. The `where` clause is appended raw
(same shape as in `findById`'s validation path);
use `whereBinds` for the values.

### `BulkOpsAsync.executeUpdateAsync`

```dart
Future<int> executeUpdateAsync({
  required String table,
  required Map<String, Object?> setters,   // non-empty
  String? where,
  List<Object?>? whereBinds,
});
```

Throws `ArgumentError` when `setters` is empty. The
engine reads the affected-row count through
SQLite's `changes()` (Postgres uses `ROW_COUNT`,
handled by the provider package).

### `BulkOpsAsync.executeDeleteAsync`

```dart
Future<int> executeDeleteAsync({
  required String table,
  String? where,
  List<Object?>? whereBinds,
});
```

Same semantics. Pass `where: null` to delete every
row (rarely what you want — usually wrapped in a
transaction by the caller).

---

## `DbInterceptor` + `InterceptorRegistry`

`DbInterceptor` is the hook contract for
cross-cutting ORM concerns: tenant filtering, audit
logs, soft-delete, encryption, query rewriting. A
`DbContext` owns one `InterceptorRegistry`; each
`DbSet<T>` shares it via `attachInterceptors`.

### The eight hooks

The interceptor has eight overrideable hooks, split
by granularity:

**Command level** (fires once per SQL command):

| Hook | Fires | Use for |
|---|---|---|
| `onQuery(QueryCommand)` | Before every SELECT | Tenant filter, query rewriting, logging. |
| `onQueryComplete(QueryResult)` | After every SELECT | Slow-query log, result transformation. |
| `onMutation(MutationCommand)` | Before every INSERT / UPDATE / DELETE | Add `created_at`, encrypt, convert DELETE to soft-delete. |
| `onMutationComplete(MutationResult)` | After every mutation | Affected-rows log, deadlock retry. |

**Entity level** (fires once per entity in a
`saveChanges` batch):

| Hook | Fires | Use for |
|---|---|---|
| `onSaveChangesStart(ChangeSet)` | At the start of `saveChanges` | Global validation, set common fields. |
| `onEntitySaving(ChangeEntry)` | Before each entity's INSERT / UPDATE / DELETE | Modify the entity itself (`created_at = DateTime.now()`, soft-delete decision). |
| `onEntitySaved(ChangeEntry, MutationResult)` | After each entity's mutation | Inspect result, log, react to errors. |
| `onSaveChangesEnd(ChangeSet, Object? error)` | At the end of `saveChanges` | Publish events, audit log, send notifications. `error` is non-null on failure. |

All hooks have a default no-op implementation.
Override only what you care about. The chain is
invoked in registration order; the output of
interceptor N becomes the input of N+1. Throwing in
any hook aborts the chain and propagates to the
caller.

### `TenantFilter` + `AuditLog` example

```dart
class TenantFilter extends DbInterceptor {
  final int tenantId;
  TenantFilter(this.tenantId);

  @override
  Future<QueryCommand> onQuery(QueryCommand cmd) async {
    if (cmd.table == 'users' && !cmd.sql.contains('WHERE')) {
      return cmd.copyWith(
        sql: '${cmd.sql} WHERE tenant_id = ?',
        binds: <Object?>[...cmd.binds, tenantId],
      );
    }
    return cmd;
  }
}

class AuditLog extends DbInterceptor {
  @override
  Future<void> onSaveChangesStart(ChangeSet changes) async {
    log.write('Saving ${changes.entries.length} changes…');
  }

  @override
  Future<void> onEntitySaved(ChangeEntry entry, MutationResult r) async {
    if (!r.isSuccess) log.write('FAILED: ${entry.entity.runtimeType} '
        '(${r.error})');
  }
}

// Wire-up:
final db = MyDbContext(sqliteProvider);
db.interceptors
  ..add(TenantFilter(42))
  ..add(AuditLog());
```

### `InterceptorRegistry`

| Member | Purpose |
|---|---|
| `interceptors` | Unmodifiable view of the registered list, in insertion order. |
| `length` / `isEmpty` / `isNotEmpty` | Cardinality checks. |
| `add(DbInterceptor)` | Append to the chain. |
| `addAll(Iterable<DbInterceptor>)` | Append many in the given order. |
| `remove(DbInterceptor)` | Remove a previously-added interceptor; returns `true` if found. |
| `clear()` | Drop every interceptor. |

The registry is empty by default — no behaviour
change for users who don't add interceptors.

### Command & result types

| Type | Purpose |
|---|---|
| `QueryCommand` | `sql`, `binds`, `table` of an upcoming SELECT. Use `copyWith` to transform. |
| `QueryResult` | `rows`, `command`, `elapsed`, `error`/`stackTrace`. `isSuccess` true when no error. |
| `MutationCommand` | `sql`, `binds`, `table`, `operation` (`'INSERT'` / `'UPDATE'` / `'DELETE'`), `entity`. |
| `MutationResult` | `rowsAffected`, `command`, `lastInsertRowId` (INSERT only), `elapsed`, `error`/`stackTrace`. |
| `ChangeSet` | `entries` (per-entity), `context`, `batchId` (monotonic counter per `saveChanges`). |
| `ChangeEntry` | `state`, `entity`, `meta`, optional `event`, optional `command`. |

---

## Eager loading (`IncludeRelation` / `IncludeOne` / `IncludeMany`)

`IncludeRelation` is the **declarative** alternative
to the callback-based `include` parameter on
`findById` / `findByIdAsync`. Each include emits a
single SQL statement with one `LEFT JOIN` per
relation (N+1 → 1 query).

`IncludeRelation` is a sealed class — only the two
documented subtypes can be instantiated.

### `IncludeOne<T, R>`

```dart
final Book? book = ctx.books.findById(1, joins: <IncludeRelation<Book, Object>>[
  IncludeOne<Book, Author>(
    navigationName: 'author',
    relatedMeta: Author.entityMeta,
    fkColumnOnT: 'author_id',
  ),
]);
```

The emitted SQL is
`SELECT … FROM books LEFT JOIN authors ON authors.id = books.author_id WHERE books.id = ? LIMIT 1`.

| Field | Required | Purpose |
|---|---|---|
| `navigationName` | yes | The navigation property name (e.g. `'author'`). |
| `relatedMeta` | yes | The `EntityMeta` of the related table. |
| `fkColumnOnT` | yes | The FK column on `T` (e.g. `'author_id'`). |

### `IncludeMany<T, R>`

```dart
final Book? book = ctx.books.findById(1, joins: <IncludeRelation<Book, Object>>[
  IncludeMany<Book, Sale>(
    navigationName: 'sales',
    relatedMeta: Sale.entityMeta,
    inverseFkColumn: 'book_id',
  ),
]);
```

The emitted SQL is
`SELECT … FROM books LEFT JOIN sales ON sales.book_id = books.id WHERE books.id = ? LIMIT 1`.

| Field | Required | Purpose |
|---|---|---|
| `navigationName` | yes | The navigation property name (e.g. `'sales'`). |
| `relatedMeta` | yes | The `EntityMeta` of the related table. |
| `inverseFkColumn` | yes | The FK column on the related table (e.g. `'book_id'`). |

### How `IncludeOne` and `IncludeMany` populate

The query result is one row per main entity. For
`IncludeOne`, the runtime picks the first non-null
related row and materialises a single `R`. For
`IncludeMany`, every non-null related row is
materialised into a `List<R>`. Both write the
result into the `NavigationRegistry` slot keyed by
`navigationName`.

If both `joins` and `include` are passed to
`findById`, the joins run first (single SQL), then
the `include` callbacks run on the resulting
entity (for post-processing).

---

## Navigation infrastructure (`NavigationPopulator` + `NavigationRegistry` + `DbSetInclude`)

These three types implement the eager-loading and
navigation-property machinery that backs `.include_`
chains and the `Include*` relations.

### `NavigationPopulator`

A static helper that populates a navigation
property for a list of source entities with a
**single batched query** (no N+1).

```dart
final orders = await ctx.orders.toListAsync_();
await NavigationPopulator.populate<Customer>(
  entities: orders,
  sourceMeta: Order.entityMeta,
  targetMeta: Customer.entityMeta,
  navigationName: 'customer',
  selectFn: (sql, binds) => provider.selectAsync(sql, binds),
);
// orders[i].customer is now populated.
```

Internally:

1. Finds the `NavigationMeta` by `navigationName`
   in `sourceMeta.navigations` (throws `StateError`
   if not found).
2. Reads the FK value from each source entity.
3. Builds a `SELECT * FROM target WHERE fk IN
   (?, ?, …)` query.
4. Materialises related entities via
   `targetMeta.fromRow` (throws `StateError` if the
   codegen didn't set one).
5. Indexes by PK and writes each related entity
   into `NavigationRegistry` under the
   `navigationName` key.

Throws `StateError` if the `EntityMeta` lacks a
`fromRow` factory or a `readColumn` reader (the
codegen sets both; a missing one is a builder bug).

### `NavigationRegistry`

A per-instance map keyed by the entity object
(identity-based via `Expando`). The codegen emits
the navigation getters as
`Customer? get customer => NavigationRegistry
.get<Customer>(this, 'customer');` so the closure
form `o.customer.name == 'John'` just works after
a population step.

| Method | Returns | Purpose |
|---|---|---|
| `get<T>(entity, name)` | `T?` | Read a navigation value. Returns `null` if not populated. |
| `set<T>(entity, name, value)` | `void` | Write a navigation value. Used by `NavigationPopulator` and the `.include_` chains. |
| `clear(entity)` | `void` | Drop every populated navigation for one entity. |
| `has(entity, name)` | `bool` | True if the navigation has been populated (even when the value is `null`, which is a valid "looked up and not found" state). |
| `all(entity)` | `Map<String, Object?>` | Snapshot of every populated navigation for diagnostics. |
| `setAll(entity, values)` | `void` | Bulk-populate from a map. |
| `getterName(NavigationMeta)` | `String` | Returns `meta.name`; exists as a hook for future snake_case → camelCase normalisation. |

Limitations: the `Expando` is identity-based and
runtime-only (does not survive serialisation).
Threading: not thread-safe; the framework assumes
single-threaded access.

### `DbSetInclude`

A small data class that records a pending
navigation include on a `DbSet<T>`:

```dart
class DbSetInclude {
  final String name;          // matches a NavigationMeta.name
  final EntityMeta targetMeta; // for materialisation
  const DbSetInclude({required this.name, required this.targetMeta});
}
```

The user enqueues one via `dbSet.include_<TNav>(name,
targetMeta)`; `toListWithIncludesAsync_` drains the
queue in FIFO order and clears it on completion.

---

## Metadata types (`EntityMeta`, `ColumnMeta`, `NavigationMeta`)

These three structs are the runtime's view of a
`@Table` class. They are **codegen-emitted** (read
at runtime; never constructed by the user) and
drive the SQL generation, navigation lookup, and
mutation flows.

### `EntityMeta`

```dart
class EntityMeta {
  final String tableName;
  final List<ColumnMeta> columns;
  final List<ColumnMeta> insertableColumns;
  final List<ColumnMeta> updatableColumns;
  final ColumnMeta primaryKey;
  final int primaryKeyIndex;
  final Object? Function(Object) pkOf;
  final Object? Function(Object, ColumnMeta)? readColumn;
  final Object Function(Map<String, Object?>)? fromRow;
  final void Function(Object, Object)? setId;
  final List<EmbeddedMeta> embeddedFields;
  final InheritanceStrategy inheritanceStrategy;
  final EntityMeta? parentMeta;
  final ColumnMeta? discriminatorColumn;
  final String? discriminatorValue;
  final Map<String, EntityMeta>? subclassMetas;  // TPH
  final String? parentTable;                      // TPT
  final ColumnMeta? joinedFkColumn;               // TPT
  final bool isAbstract;                          // TPC root
  final sync.ConflictResolver? conflictResolver;  // sync merge
  final List<NavigationMeta> navigations;

  List<ColumnMeta> get allColumns;          // own + embedded + TPH
  List<ColumnMeta> get effectiveInsertableColumns;
  List<ColumnMeta> get effectiveUpdatableColumns;
  String sqlColumnName(ColumnMeta c);       // applies embedded prefix
  EntityMeta resolveForDiscriminator(Object? value); // TPH dispatch
  String createTableDdl();                  // → CREATE TABLE IF NOT EXISTS
  List<String> createIndexStatements();     // → CREATE INDEX statements
  String createFullSchemaDdl();             // DDL + indexes concatenated
}
```

| Field | Role in codegen |
|---|---|
| `tableName` | The SQL name of the table (snake_case). |
| `columns` | The flat list of `@Column` / `@PrimaryKey` / `@ForeignKey` fields. |
| `insertableColumns` / `updatableColumns` | Subset of `columns` allowed in INSERT / UPDATE (auto-increment PKs are excluded from the INSERT list). |
| `primaryKey` + `primaryKeyIndex` | Single primary key column. |
| `pkOf(entity)` | Reads the PK value from an instance. Used for back-propagation and `untrack`. |
| `readColumn(entity, col)` | Reads a column value; preferred over `RecordLike.readField` because it knows about codegen-emitted field getters. |
| `fromRow(row)` | Materialises an entity from a `Map<String, Object?>`. The runtime cannot read rows without this. |
| `setId(entity, id)` | Codegen-emitted setter for the PK. Required for back-propagation after INSERT. Throws `StateError` if the PK field is `final`. |
| `embeddedFields` | The list of `EmbeddedMeta` flattened into the parent table. |
| `navigations` | One `NavigationMeta` per `@ForeignKey` (and per reverse-FK for 1:many). |
| `inheritanceStrategy` + TPH fields | The runtime dispatches row materialisation to the right child meta via `resolveForDiscriminator`. |
| `conflictResolver` | LWW override during sync; defaults to remote-wins. |

### `ColumnMeta`

```dart
class ColumnMeta {
  final String sqlName;
  final String dartField;
  final Type dartType;
  final bool nullable;
  final String? defaultLiteral;
  final bool isPrimaryKey;
  final bool isAutoIncrement;
  final bool isForeignKey;
  final String? foreignTable;
  final String? foreignColumn;
  final bool isIndexed;
  final bool isUniqueIndex;
  final String? indexName;
  final OnDeleteAction onDelete;
}
```

`fkClause(c)` (in `column_meta.dart`) emits the
`REFERENCES … [ON DELETE …]` SQL fragment for an
FK column, or the empty string for non-FK columns.

### `NavigationMeta`

```dart
class NavigationMeta {
  final String name;             // getter name on T
  final String fkColumn;         // FK field on T (dart field name)
  final String targetTable;      // snake_case
  final String targetColumn;     // snake_case
  final Type targetDartType;
  final bool isCollection;       // 1:1 (false) or 1:many (true)
  final String? reverseFkColumn; // for 1:many only
  final ColumnMeta? fkColumnMeta;
}
```

The runtime uses this list to:

1. Generate the navigation getter (codegen).
2. Translate `o.customer.name` in a closure to a
   JOIN (SQL provider).
3. Implement `.include_<TNav>()` for eager loading.
4. Detect N+1 patterns (lint rule).

---

## `EntityRegistry`

The global registry of `@Table` entities. Populated
by the codegen's `register<X>EntityMeta` helpers
inside `d_rocket_registry.g.dart`'s `initializeD`,
and read by `DbContext.entityMetaFor<T>` and
`entityMetaForRaw(entity)` (for dynamic dispatch
in `saveChangesAsync`).

```dart
class EntityRegistry {
  static void register<T>(EntityMeta meta);
  static EntityMeta? tryMetaFor(Type t); // soft-fail
  static EntityMeta metaFor(Type t);     // throws StateError if missing
  static void reset();                   // for tests
  static Iterable<Type> get registeredTypes;
}
```

The registry is **global** on purpose: `DbContext`
does not own a per-context registry, and the
per-class `static EntityMeta entityMeta` is the
primary source of truth used by `DbSet<T>`. The
global registry exists for value-typed lookup when
a generic `Object?` value is all the caller has
(e.g. `saveChangesAsync` resolving the meta of a
tracked entry by runtime type).

`DbContext.entityMetaForRaw(entity)` wraps
`EntityRegistry.metaFor` and returns a minimal
placeholder meta when the type is unregistered
(some unit tests construct entities without the
codegen — the real meta is still on the DbSet for
SQL emission).

---

## Inheritance (`InheritanceStrategy`)

`InheritanceStrategy` mirrors EF Core's three
inheritance modes.

```dart
enum InheritanceStrategy { none, tph, tpt, tpc }
```

| Value | Meaning |
|---|---|
| `none` (default) | The entity has no parent class. DDL is one table with the entity's columns. |
| `tph` (Table-Per-Hierarchy) | The entity is either the root of a TPH hierarchy (a single table holds the root + every child, with a discriminator column telling them apart) or a child of such a hierarchy. |
| `tpt` (Table-Per-Type) | The entity is the root of a TPT hierarchy (the root owns its own table) or a child (the child owns its own table with its specific columns + an FK to the root's PK; a JOIN materialises the full row). |
| `tpc` (Table-Per-Concrete-Class) | The entity is the root of a TPC hierarchy (the root has no table — it's a conceptual type) or a leaf (the leaf owns its own table with all the columns — root's + leaf's — duplicated). No JOINs needed. |

### Example: TPH

```dart
@Table.tph(name: 'animals', children: {'dog': 'Dog', 'cat': 'Cat'})
class Animal extends Record {
  @PrimaryKey()
  final int id;

  @Column()
  final String name;

  @Column(discriminator: true)
  final String kind; // 'dog' or 'cat'
}

@Table(discriminator: 'dog')
class Dog extends Animal {
  @Column()
  final String breed;
}

@Table(discriminator: 'cat')
class Cat extends Animal {
  @Column()
  final bool indoor;
}
```

`DbSet<Animal>.toList()` materialises `Dog` and
`Cat` instances automatically, picked by
`meta.discriminatorColumn` + `meta.resolveForDiscriminator`.

`@Table.tpc(...)` and `@Table.tph(...)` are
convenience constructors that set
`inheritance: InheritanceStrategy.tph` (or `.tpc`)
and forward the other fields.

---

## Foreign-key `ON DELETE` actions (`OnDeleteAction`)

`OnDeleteAction` controls what the database does
when a referenced parent row is deleted. Maps
directly to SQLite's `ON DELETE CASCADE / SET NULL /
RESTRICT / NO ACTION` (and EF Core's `OnDelete`
enum, for parity).

```dart
enum OnDeleteAction { cascade, setNull, restrict, noAction }
```

| Value | Effect at the DB level |
|---|---|
| `cascade` | When the parent is deleted, the dependent rows are deleted recursively. |
| `setNull` | When the parent is deleted, the FK column on the dependents is set to `NULL`. The column MUST be nullable. |
| `restrict` | The DB rejects the `DELETE` on the parent if any dependent row references it. |
| `noAction` (default) | No `ON DELETE` clause is emitted. The DB uses its own default (`NO ACTION` in SQLite). |

The action is stored on `ColumnMeta.onDelete` and
emitted via `fkClause(c)` in the DDL.

### Example

```dart
@ForeignKey(
  table: 'customers',
  column: 'id',
  onDelete: OnDeleteAction.cascade, // not actually exposed as a
                                   // parameter today — see TODO.
)
```

> **Status (2.0).** The `OnDeleteAction` enum is
> fully defined on `ColumnMeta.onDelete`, but the
> `@ForeignKey` annotation does not yet expose it
> as a parameter. Set it via a hand-written
> `ColumnMeta` in a test fixture, or wait for the
> next codegen pass. The `fkClause` helper already
> emits the correct SQL fragment.

---

## Code-first migrations (`@Migration`, `MigrationBase`)

d_rocket ships a code-first migration system (EF
Core's `Migration` / sqflite's `onUpgrade` style).
Each migration is a top-level function annotated
with `@Migration`; the codegen emits a
`MigrationBase` subclass with the `up` body and
records the migration in the central registry.

```dart
@Migration(id: '001', name: 'Initial schema')
MigrationBase initialSchema => _$_InitialSchema;
```

> **Naming note.** The annotation class is named
> `Migration` and the abstract base class is named
> `MigrationBase`. The two names are deliberately
> distinct so the same library can hold `@Migration`
> AND the codegen-emitted `extends MigrationBase`
> without a same-library name collision.

### `@Migration` annotation

```dart
const Migration({required String id, required String name});
```

| Parameter | Required | Purpose |
|---|---|---|
| `id` | yes | Stable, lexicographically-ordered identifier. Primary key in the `_d_rocket_migrations` table. The conventional style is `'001'`, `'002'`, … (zero-padded numeric). |
| `name` | yes | Human-readable name. Shown in the tracking table and in error messages. |

### `MigrationBase`

```dart
abstract class MigrationBase {
  String get id;
  String get name;
  int get version;          // monotonic int; parses `id` by default
  void up(MigrationExecutor exec);
  void down(MigrationExecutor exec) => throw UnsupportedError(...);
  Future<void> upAsync(AsyncMigrationExecutor exec);
  Future<void> downAsync(AsyncMigrationExecutor exec);
}
```

| Member | Purpose |
|---|---|
| `id` | The migration id (matches the annotation's `id`). |
| `name` | The migration name (matches the annotation's `name`). |
| `version` | Monotonic `int` schema version. The default parses `id` as an `int` for backward compatibility with `'001'` / `'002'` ids. For date-based ids (e.g. `'2026-06-23-add-users'`), override this to return the monotonic version explicitly. The `MigrationStrategy` runner uses this to pick the subset to apply on upgrade / rollback. |
| `up(exec)` | Apply the migration. Receives a `MigrationExecutor`. |
| `down(exec)` | Reverse the migration. Defaults to `UnsupportedError` — the migration is irreversible until the user overrides this. |
| `upAsync(exec)` | Async counterpart of `up`. Default implementation delegates to `up` through the executor; override to use async-only features. |
| `downAsync(exec)` | Async counterpart of `down`. Same defaulting rule. |

`MigrationBase` throws `StateError` when `version`
is read and the `id` is not parseable as an `int`
AND `version` was not explicitly overridden. The
`MigrationStrategy` runner uses `version` to decide
which subset of migrations to apply / rollback.

The migration runner is invoked by
`DbContext.migrate` / `migrateAsync` /
`migrateToAsync` / `migrateStrategyAsync` (see
[Defining a `DbContext` subclass](#defining-a-rocketdbcontext-subclass)).

---

## `MigrationStrategy` (declarative + imperative)

`MigrationStrategy` is the ADO.NET / sqflite_common_ffi
/ EF Core way of declaring migrations: a
version-tagged declaration that the runner can apply
fresh, upgrade incrementally, or roll back.

```dart
await Db.open(
  path: 'app.db',
  strategy: MigrationStrategy(
    version: 5,
    migrations: <MigrationBase>[
      M001CreateUsers,
      M002AddEmail,
      M003AddPosts,
      M004AddPostAuthorId,
      M005CreateSessions,
    ],
  ),
);
```

The runner reads the database's current version
from `_d_rocket_migrations.version` and either:

* applies all migrations (fresh install),
* applies the subset in `(current, version]` (upgrade),
* rolls back the subset in `(version, current]`
  in reverse (downgrade),
* or no-ops when `current == version`.

### Constructor

```dart
const MigrationStrategy({
  required int version,
  List<MigrationBase> migrations = const <MigrationBase>[],
  Future<void> Function(MigrationExecutor, int)? onCreate,
  Future<void> Function(MigrationExecutor, int, int)? onUpgrade,
  Future<void> Function(MigrationExecutor, int, int)? onDowngrade,
  bool trackMigrations = true,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `version` | (required) | The target schema version. After running, the database is at this version. |
| `migrations` | `[]` | The full ordered list of available migrations. Used by the **declarative** mode to pick the subset. |
| `onCreate` | `null` | Imperative-mode callback for fresh installs. Receives `(exec, version)`. |
| `onUpgrade` | `null` | Imperative-mode callback for upgrades. Receives `(exec, oldVersion, newVersion)`. The user branches on `oldV`: `if (oldV < 2) await M002.upAsync(exec); …`. |
| `onDowngrade` | `null` | Imperative-mode callback for downgrades. Same shape as `onUpgrade`. A `null` callback with declarative `down()`s left out throws `StateError`. |
| `trackMigrations` | `true` | When `true` (declarative default), the runner records each applied migration in `_d_rocket_migrations`. When `false` (imperative default when `onCreate` / `onUpgrade` are provided), the user manages the table. |

### Two execution modes

```dart
bool get isImperative =>
    onCreate != null || onUpgrade != null || onDowngrade != null;
```

| Mode | When | Behaviour |
|---|---|---|
| **Declarative** (default) | `migrations` is non-empty and no callbacks are provided | The runner picks the subset whose `version` is in `(current, target]` and runs them in order. Each migration is recorded in `_d_rocket_migrations` (when `trackMigrations: true`). |
| **Imperative** | `onCreate` / `onUpgrade` / `onDowngrade` is provided | The user is responsible for the branching logic. `trackMigrations` is `false` by default — the user manages the table manually. |

### Imperative-mode example (sqflite-style)

```dart
MigrationStrategy(
  version: 5,
  trackMigrations: false,
  onCreate: (exec, v) async {
    await M001CreateUsers.upAsync(exec);
    await M002AddEmail.upAsync(exec);
  },
  onUpgrade: (exec, oldV, newV) async {
    if (oldV < 2) await M002AddEmail.upAsync(exec);
    if (oldV < 3) await M003AddPosts.upAsync(exec);
  },
  onDowngrade: (exec, oldV, newV) async {
    if (oldV > 2) await M002AddEmail.downAsync(exec);
    if (oldV > 1) await M001CreateUsers.downAsync(exec);
  },
);
```

---

## `AppliedMigration`

A typed struct that materialises one row of the
`_d_rocket_migrations` tracking table. Returned by
`MigrationRunner.applied` / `appliedAsync`, and by
`DbContext.appliedAsync`. Used by the CLI's `status`
subcommand and by startup-time logging.

```dart
class AppliedMigration {
  final String id;          // primary key in the tracking table
  final String name;        // human-readable
  final int? version;       // nullable for pre—10 entries
  final DateTime appliedAt; // parsed from the ISO-8601 `applied_at`

  factory AppliedMigration.fromRow(Map<String, Object?> row);
  const AppliedMigration({
    required this.id,
    required this.name,
    required this.version,
    required this.appliedAt,
  });

  @override
  String toString();
  @override
  bool operator ==(Object other);
  @override
  int get hashCode;
}
```

| Field | Purpose |
|---|---|
| `id` | The string id of the migration (`'001'`, `'002'`, …). |
| `name` | The human-readable name. Free-form; set by the author. |
| `version` | The integer version. `null` for pre-2.0 entries with non-numeric ids that haven't been backfilled. New entries always carry an explicit version. |
| `appliedAt` | The UTC instant at which the migration was applied, parsed from the ISO-8601 `applied_at` column. |

`fromRow` expects the columns `id`, `name`,
`version`, `applied_at` and throws `FormatException`
when any of the required string columns is of the
wrong type. The `version` column tolerates `null`,
`int`, `String`, `num`, or any other type (anything
unparseable becomes `null`).

---

## Error hierarchy (`DatabaseException`)

`DatabaseException` is the engine-agnostic
exception type. Every engine (SQLite, Postgres, web)
wraps its native exception (e.g. SQLite's
`SqliteException`, Postgres's `PgException`) in a
`DatabaseException` so that application code can
catch one type without knowing which engine
produced the error.

```dart
class DatabaseException implements Exception {
  DatabaseException(this.message, {this.cause, this.sql, this.code});

  final String message;        // user-facing
  final Object? cause;         // the original engine exception
  final String? sql;           // the SQL statement, if known
  final Object? code;          // the engine error code, if any

  @override
  String toString();            // includes message + sql + code + cause
}
```

| Field | Purpose |
|---|---|
| `message` | User-facing description. Safe to log and surface to the user. |
| `cause` | The original engine exception (e.g. `SqliteException`). Keep for debugging; `.toString()` shows engine-specific details. |
| `sql` | The SQL statement that produced the error. May be `null` for non-statement errors (e.g. open failures). |
| `code` | Engine-specific error code (e.g. SQLite's extended error code). May be `null`. |

### Catch pattern

```dart
try {
  await ctx.saveChangesAsync();
} on DatabaseException catch (e) {
  log.write('Database error: ${e.message}');
  if (e.cause != null) log.write('  cause: ${e.cause}');
}
```

This single catch works against any of the three
2.0.0 engines. The `cause` is the unwrapped engine
exception for fine-grained handling (e.g. catching
a specific Postgres error code).

---

## SQL log redaction (`redactPragmaKey`)

A small helper that obfuscates the value of a
`PRAGMA key = '…'` or `PRAGMA rekey = '…'`
statement in a SQL log line. The literal is
replaced with `'***'`.

```dart
String redactPragmaKey(String sql);
```

### Example

```dart
redactPragmaKey("PRAGMA key = 'hunter2'");
// → "PRAGMA key = '***'"

redactPragmaKey("PRAGMA rekey = 'O''Brien'");
// → "PRAGMA rekey = '***'"

redactPragmaKey("SELECT * FROM users");
// → "SELECT * FROM users"  (unmodified)
```

The function is case-insensitive and tolerant of
whitespace variations. It only matches the
single-quoted form (which is what
`d_rocket_engine_sqlite` itself emits when
applying the key). The `''` SQL-escape for an
apostrophe inside the literal is preserved.

`PRAGMA key` / `PRAGMA rekey` are SQLCipher
statements (the form that ships in
`d_rocket_engine_sqlite`). The function lives in
the core so the REST layer's `LoggingInterceptor`
can use it without depending on a specific engine
package.

### Limitations

* Does NOT detect keys passed via a `?` placeholder
  — `PRAGMA` does not accept bound parameters in
  SQLite, so `PRAGMA key = ?` is a no-op in the
  engine and has no key value to redact.

### Use pattern

```dart
class LoggingInterceptor extends DbInterceptor {
  @override
  Future<MutationCommand> onMutation(MutationCommand cmd) async {
    log.write(redactPragmaKey(cmd.sql));
    return cmd;
  }
}
```
