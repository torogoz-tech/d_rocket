/// End-to-end tests for the `where_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  // The 3 demo predicates, lifted into the Expr DSL. These are the
  // canonical examples the spike validated; now they run through
  // IQueryable in production code.
  final adults = Expr.lambda(
    [Expr.param('u')],
    Expr.binary('>', Expr.member(Expr.param('u'), 'age'), Expr.const_(18)),
  );
  final startsWithA = Expr.lambda(
    [Expr.param('u')],
    Expr.call(
      Expr.member(Expr.param('u'), 'name'),
      'startsWith',
      [Expr.const_('A')],
    ),
  );
  final idIs5OrHasEmail = Expr.lambda(
    [Expr.param('u')],
    Expr.binary(
      '||',
      Expr.binary('==', Expr.member(Expr.param('u'), 'id'), Expr.const_(5)),
      Expr.binary('!=', Expr.member(Expr.param('u'), 'email'), Expr.null_),
    ),
  );

  final users = [
    User(id: 1, name: 'Alice', age: 25, email: 'a@x.com'),
    User(id: 2, name: 'Bob', age: 17, email: null),
    User(id: 3, name: 'Carol', age: 30, email: 'c@x.com'),
    User(id: 4, name: 'Dan', age: 40, email: null),
    User(id: 5, name: 'Eve', age: 16, email: 'e@x.com'),
  ];

  group('where_ — end-to-end', () {
    test('u.age > 18', () {
      final result = users.asQueryable().where_(adults).toList();
      expect(result.map((u) => u.id), [1, 3, 4]);
    });

    test('u.name.startsWith("A")', () {
      final result = users.asQueryable().where_(startsWithA).toList();
      expect(result.map((u) => u.id), [1]);
    });

    test('u.id == 5 || u.email != null', () {
      final result = users.asQueryable().where_(idIs5OrHasEmail).toList();
      // id == 5: Eve (5). email != null: Alice (1), Carol (3), Eve (5).
      expect(result.map((u) => u.id), [1, 3, 5]);
    });

    test('chaining multiple where_ calls', () {
      final result =
          users.asQueryable().where_(adults).where_(startsWithA).toList();
      // Adults AND starts with 'A' = Alice.
      expect(result.map((u) => u.id), [1]);
    });

    test('empty result is well-defined', () {
      final noAdults = users.where((u) => u.age < 0).toList();
      final result = noAdults.asQueryable().where_(adults).toList();
      expect(result, isEmpty);
    });
  });

  group('where_ — argument validation', () {
    test('non-LambdaExpr predicate throws', () {
      expect(
        () => users.asQueryable().where_(Expr.const_(true)),
        throwsArgumentError,
      );
    });

    test('multi-parameter Lambda throws', () {
      final bad = Expr.lambda(
        [Expr.param('u'), Expr.param('v')],
        Expr.const_(true),
      );
      expect(
        () => users.asQueryable().where_(bad),
        throwsArgumentError,
      );
    });
  });

  group('where_ — works on Map rows (the SQL row shape)', () {
    final rows = [
      {'id': 1, 'age': 25},
      {'id': 2, 'age': 17},
      {'id': 3, 'age': 30},
    ];
    final predicate = Expr.lambda(
      [Expr.param('row')],
      Expr.binary(
        '>',
        Expr.member(Expr.param('row'), 'age'),
        Expr.const_(18),
      ),
    );

    test('filters a List<Map<String, Object?>>', () {
      final result = rows.asQueryable().where_(predicate).toList();
      expect(result, [
        {'id': 1, 'age': 25},
        {'id': 3, 'age': 30},
      ]);
    });
  });

  group('where_ — deferred execution', () {
    test('asQueryable does not iterate the source', () {
      var iterCount = 0;
      final source = Iterable.generate(1000, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      final q = source.asQueryable();
      expect(iterCount, 0, reason: 'asQueryable() did not iterate');
      q.toList();
      expect(iterCount, 1000, reason: 'toList() iterated all 1000');
    });

    test('where_ does not iterate until a terminal operator', () {
      var iterCount = 0;
      final source = Iterable.generate(1000, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      final q = source.asQueryable().where_(
            Expr.lambda(
              [Expr.param('i')],
              Expr.binary(
                '<',
                Expr.param('i'),
                Expr.const_(500),
              ),
            ),
          );
      expect(iterCount, 0, reason: 'no iteration yet');
      final r = q.toList();
      expect(r.length, 500);
      expect(iterCount, 1000, reason: 'toList iterated all source items');
    });
  });
}
