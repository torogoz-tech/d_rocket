/// (Quickstart): the modern d_rocket
/// API at a glance. Single file showing the
/// EFCore-style usage.
///
/// API contract:
/// 1. The first call after `db.set<T>` is clean
/// (no underscore): `.where(...)`. This is a
/// `DbSetLinqExtension` that bridges to the
/// `Queryable<T>` LINQ surface.
/// 2. Subsequent operators on the chain use the
/// trailing-underscore names on `Queryable<T>`
/// (`.where_`, `.orderBy_`, `.take_`, …) because
/// `Queryable<T>` extends `Iterable<T>` and
/// `where`/`take`/`skip`/`orderBy` collide with
/// `Iterable`'s built-ins. The underscore
/// convention is the canonical way to disambiguate.
/// 3. The terminal is suffixed: `.toListAsync_`,
/// `.countAsync_`. These follow the `_*`
/// convention on `Queryable<T>` (suffixed
/// underscore to avoid clashes with `Iterable`).
/// Note: the first call on `DbSet<T>` is
/// clean (no underscore): `.where(...)`, because
/// the bridge extension runs on `DbSet<T>`, not
/// on `Queryable<T>`.
///
/// Note: this example was moved from `lib/example/`
/// to `example/` in v1.0.1. It is **not** part of
/// the published library.
import 'package:d_rocket/d_rocket.dart';

import 'package:d_rocket/d_rocket_registry.g.dart';

/// Stub entity — real code uses a `@Table`
/// class with codegen.
class Person {
  Person({required this.id, required this.name, required this.age});
  final int id;
  final String name;
  final int age;
}

///: the canonical user-facing flow.
Future<void> main() async {
  // 1. Register all `@Table` entities (codegen-emitted).
  initializeD();

  // 2. Open the database. Returns a Db facade.
  final Db db = await Db.open(
    path: 'myapp.db',
    onCreate: (Db db) async {
      // First-run setup: apply migrations.
      await db.migrate();
    },
  );

  // 3. Insert.
  db.set<Person>().add(Person(id: 1, name: 'Juan', age: 30));
  db.set<Person>().add(Person(id: 2, name: 'Maria', age: 25));
  await db.saveChanges();

  // 4. Query — direct LINQ on DbSet. No `asQueryable`.
  //
  // The first operator call is on `DbSet<T>` (clean).
  // The chain after that is on `Queryable<T>` and
  // uses the trailing-underscore convention
  // (see file-level doc above for the why).
  // ignore: unused_local_variable
  final List<Person> adults = await db
      .set<Person>()
      .where(Expr.lambda(
        <Expr>[Expr.param('p')],
        Expr.binary(
          '>=',
          Expr.member(Expr.param('p'), 'age'),
          Expr.const_(18),
        ),
      ))
      .orderBy_(Expr.lambda(
        <Expr>[Expr.param('p')],
        Expr.member(Expr.param('p'), 'name'),
      ))
      .take_(10)
      .toListAsync_();

  // 5. Reactive (Stream re-emits on every change).
  // ignore: unused_local_variable
  final Stream<List<Person>> stream = db
      .set<Person>()
      .where(Expr.lambda(
        <Expr>[Expr.param('p')],
        Expr.binary(
          '>=',
          Expr.member(Expr.param('p'), 'age'),
          Expr.const_(18),
        ),
      ))
      .watch();

  // 6. Close.
  await db.close();
}
