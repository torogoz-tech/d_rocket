/// End-to-end tests for the aggregate LINQ operators.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25),
    User(id: 2, name: 'Bob', age: 17),
    User(id: 3, name: 'Carol', age: 30),
  ];

  final byAge = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'age'),
  );
  final byName = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'name'),
  );

  group('count_', () {
    test('no predicate', () {
      expect(users.asQueryable().count_(), 3);
    });

    test('with predicate', () {
      final adults = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '>=',
          Expr.member(Expr.param('u'), 'age'),
          Expr.const_(18),
        ),
      );
      expect(users.asQueryable().count_(where: adults), 2);
    });

    test('empty source', () {
      expect(<User>[].asQueryable().count_(), 0);
    });
  });

  group('longCount_', () {
    test('matches count_', () {
      expect(users.asQueryable().longCount_(), 3);
    });
  });

  group('sum_', () {
    test('sum of ages', () {
      expect(users.asQueryable().sum_(byAge), 72);
    });

    test('empty source returns 0 (Dart-ergonomic, differs from C#)', () {
      expect(<User>[].asQueryable().sum_(byAge), 0);
    });

    test('chained from select_', () {
      // project to ages and sum.
      final ages = users.asQueryable().select_<int>(byAge);
      // sum_ takes a selector, not an int. The chained version
      // requires an explicit cast or a sum over the int queryable.
      // For, the sum_ selector is required; for ints, the
      // selector is just (n) => n.
      final sumAges = ages.sum_(
        Expr.lambda([Expr.param('n')], Expr.param('n')),
      );
      expect(sumAges, 72);
    });
  });

  group('average_', () {
    test('average of ages', () {
      expect(users.asQueryable().average_(byAge), closeTo(24.0, 0.001));
    });

    test('empty source throws', () {
      expect(
        () => <User>[].asQueryable().average_(byAge),
        throwsStateError,
      );
    });
  });

  group('min_ / max_', () {
    test('min age', () {
      expect(users.asQueryable().min_(byAge), 17);
    });

    test('max age', () {
      expect(users.asQueryable().max_(byAge), 30);
    });

    test('min name (alphabetical)', () {
      expect(users.asQueryable().min_(byName), 'Alice');
    });

    test('max name (alphabetical)', () {
      expect(users.asQueryable().max_(byName), 'Carol');
    });

    test('empty source throws', () {
      expect(
        () => <User>[].asQueryable().min_(byAge),
        throwsStateError,
      );
      expect(
        () => <User>[].asQueryable().max_(byAge),
        throwsStateError,
      );
    });
  });

  group('aggregate_', () {
    test('concatenate names', () {
      // acc='; ', x.name → 'Alice; Bob; Carol' (sort of; depends on order).
      // We'll just compute the alphabetical join.
      final result = users.asQueryable().aggregate_<String>(
            seed: '',
            func: Expr.lambda(
              [Expr.param('acc'), Expr.param('u')],
              Expr.binary(
                '+',
                Expr.param('acc'),
                Expr.member(Expr.param('u'), 'name'),
              ),
            ),
          );
      expect(result, 'AliceBobCarol');
    });

    test('sum via aggregate', () {
      final result = users.asQueryable().aggregate_<int>(
            seed: 0,
            func: Expr.lambda(
              [Expr.param('acc'), Expr.param('u')],
              Expr.binary(
                '+',
                Expr.param('acc'),
                Expr.member(Expr.param('u'), 'age'),
              ),
            ),
          );
      expect(result, 72);
    });

    test('empty source returns seed', () {
      final result = <User>[].asQueryable().aggregate_<int>(
            seed: 42,
            func: Expr.lambda(
              [Expr.param('acc'), Expr.param('u')],
              Expr.const_(0),
            ),
          );
      expect(result, 42);
    });

    test('wrong arity (func with 1 param) throws', () {
      expect(
        () => users.asQueryable().aggregate_<int>(
              seed: 0,
              func: Expr.lambda([Expr.param('a')], Expr.const_(1)),
            ),
        throwsArgumentError,
      );
    });
  });
}
