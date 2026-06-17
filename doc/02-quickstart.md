# 02 — Quickstart

Five minutes from `pubspec.yaml` to a working query.

## Step 1 — Add the dependencies

Edit your `pubspec.yaml`:

```yaml
name: my_app
description: My first d_rocket app
publish_to: none

environment:
  sdk: ^3.5.0
  flutter: ">=3.10.0"

dependencies:
  d_rocket: ^1.0.0

dev_dependencies:
  d_rocket_builder: ^1.0.0
  build_runner: ^2.4.13
```

Then fetch and run the generator:

```bash
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

The first run creates `d_rocket_registry.g.dart` next to
your annotated source files. Re-run the generator after
every schema or API change.

## Step 2 — Define an entity

Mark a class with `@Table` and add a primary key +
column annotations:

```dart
// lib/todo.dart
import 'package:d_rocket/d_rocket.dart';

@Table('todos')
class Todo {
  @PrimaryKey(autoIncrement: true)
  final int id;

  @Column()
  final String title;

  @Column()
  final bool done;

  @Column(name: 'created_at')
  final DateTime createdAt;

  Todo({
    this.id = 0,
    required this.title,
    this.done = false,
    required this.createdAt,
  });
}
```

The codegen emits a per-class `fromRow` row materialiser
and a `setId` back-propagation hook (so a DB-assigned
`id` is reflected in the in-memory entity after the
insert). It also wires the entity into the central
`initializeD()` registry.

## Step 3 — Open the database

In `main()`, register everything with one call and
open the database:

```dart
// lib/main.dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Wire every @Serializable, @RestClient, and
  //    @Table in the project.
  initializeD();

  // 2. Open the local SQLite database. With
  //    `entityMetas:` and `autoMigrate: true` (1.2.0+),
  //    d_rocket computes the diff between the
  //    codegen-emitted schema and the last applied
  //    snapshot, applies the safe changes (CREATE
  //    TABLE / CREATE INDEX / ADD COLUMN nullable or
  //    with default) in a single transaction, and
  //    reports the unsafe changes (DROP / MODIFY) via
  //    `db.pendingSchemaDiff()`. See
  //    [10-migrations.md](10-migrations.md#auto-migrations-120)
  //    for the full design.
  final db = await Db.open(
    path: 'app.db',
    entityMetas: <EntityMeta>[Todo.entityMeta],
    autoMigrate: true,
  );

  // 3. Hand the database to your app.
  runApp(MyApp(db: db));
}
```

If you have hand-written `MigrationBase`s (e.g.
data migrations), pass a `MigrationStrategy` to
`Db.open` as well — the auto-migrator runs **after**
the manual one, and the two do not interfere.

```dart
final db = await Db.open(
  path: 'app.db',
  strategy: MigrationStrategy(
    version: 4,
    migrations: [M001(), M002(), M003(), M004()],
  ),
  entityMetas: <EntityMeta>[Todo.entityMeta],
  autoMigrate: true,
);
```

## Step 4 — Insert a row

```dart
db.set<Todo>().add(Todo(
  title: 'Ship d_rocket 1.0',
  done: false,
  createdAt: DateTime.now(),
));

// Batch multiple inserts; a single transaction commits
// the whole change set.
db.set<Todo>().add(Todo(
  title: 'Write docs',
  done: false,
  createdAt: DateTime.now(),
));

await db.saveChanges();
```

`saveChanges()` returns the number of rows affected. The
whole batch runs in a single transaction — if any insert
fails, the entire batch rolls back and the change
tracker is restored to its pre-batch state.

## Step 5 — Query

The query is composed as a chain of operators, then
materialized by a terminal:

```dart
final pending = await db
    .set<Todo>()
    .where(Expr.lambda(
      <Expr>[Expr.param('p')],
      Expr.binary(
        '==',
        Expr.member(Expr.param('p'), 'done'),
        Expr.const_(false),
      ),
    ))
    .orderBy_(Expr.lambda(
      <Expr>[Expr.param('p')],
      Expr.member(Expr.param('p'), 'createdAt'),
    ))
    .toListAsync_();

print('${pending.length} pending todos');
```

`where` (clean — no underscore) is the bridge from
`DbSet<T>` to `Queryable<T>`. After the bridge, every
operator uses the trailing-underscore convention
(`orderBy_`, `take_`, `toList_`, `toListAsync_`) to
disambiguate from `Iterable<T>`'s built-ins. See
[06-layer-3-linq.md](06-layer-3-linq.md#the-underscore-convention)
for the why.

## Step 6 — Watch (reactive)

`watch()` returns a `Stream` that re-emits whenever the
underlying table changes:

```dart
Stream<List<Todo>> pendingTodos() => db
    .set<Todo>()
    .where(Expr.lambda(
      <Expr>[Expr.param('p')],
      Expr.binary(
        '==',
        Expr.member(Expr.param('p'), 'done'),
        Expr.const_(false),
      ),
    ))
    .watch();

pendingTodos().listen((todos) {
  print('now ${todos.length} pending todos');
});
```

Wire it to a `StreamBuilder` (Flutter) or any other
reactive consumer. The stream re-emits on every
`saveChanges()` that affects the table.

## The full app

In 50 lines:

```dart
// lib/main.dart
import 'package:d_rocket/d_rocket.dart';
import 'package:my_app/d_rocket_registry.g.dart';
import 'package:my_app/todo.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializeD();
  final db = await Db.open(
    path: 'app.db',
    onCreate: (db) async {
      await db.exec('''
        CREATE TABLE todos (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          title      TEXT    NOT NULL,
          done       INTEGER NOT NULL DEFAULT 0,
          created_at TEXT    NOT NULL
        )
      ''');
    },
  );
  runApp(MyApp(db: db));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.db});
  final Db db;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Todos')),
        body: StreamBuilder<List<Todo>>(
          stream: db
              .set<Todo>()
              .where(Expr.lambda(
                <Expr>[Expr.param('p')],
                Expr.binary('==',
                  Expr.member(Expr.param('p'), 'done'),
                  Expr.const_(false)),
              ))
              .watch(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final todos = snapshot.data!;
            return ListView.builder(
              itemCount: todos.length,
              itemBuilder: (context, i) {
                final t = todos[i];
                return ListTile(
                  title: Text(t.title),
                  subtitle: Text('created ${t.createdAt}'),
                );
              },
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            db.set<Todo>().add(Todo(
              title: 'New todo',
              done: false,
              createdAt: DateTime.now(),
            ));
            await db.saveChanges();
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
```

## What's next?

You've seen the four most common operations: open,
insert, query, watch. The rest of the framework
exposes:

- **Layer 1** — JSON serialization for wire and storage
  ([04-layer-1-serialization.md](04-layer-1-serialization.md))
- **Layer 2** — typed REST clients with retry and circuit
  breakers ([05-layer-2-rest.md](05-layer-2-rest.md))
- **Layer 3** — every LINQ operator ([06-layer-3-linq.md](06-layer-3-linq.md))
- **Layer 5** — offline-first sync ([08-layer-5-sync.md](08-layer-5-sync.md))
- **Layer 6** — typed WebSocket / SSE ([09-layer-6-realtime.md](09-layer-6-realtime.md))
- **Migrations** — schema-versioned upgrades and downgrades
  ([10-migrations.md](10-migrations.md))
- **Cookbook** — real recipes ([12-cookbook.md](12-cookbook.md))

If you ran into trouble during the quickstart, the
[03 — Installation](03-installation.md) guide covers
the most common pitfalls.
