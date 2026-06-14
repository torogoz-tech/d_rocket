/// End-to-end tests for the `takeWhile_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25),
    User(id: 2, name: 'Bob', age: 17),
    User(id: 3, name: 'Carol', age: 30),
    User(id: 4, name: 'Dan', age: 18),
    User(id: 5, name: 'Eve', age: 16),
  ];

  // age < 30: 25, 17 (yes), 30 (no, stop).
  // We include a "stop element" that is not included.
  final predicate = Expr.lambda(
    [Expr.param('u')],
    Expr.binary(
      '<',
      Expr.member(Expr.param('u'), 'age'),
      Expr.const_(30),
    ),
  );

  group('takeWhile_', () {
    test('takes elements while predicate holds', () {
      final result = users.asQueryable().takeWhile_(predicate).toList();
      expect(result.map((u) => u.id), [1, 2]); // stops at Carol (age 30).
    });

    test('predicate always true returns all elements', () {
      final all = Expr.lambda(
        [Expr.param('u')],
        Expr.const_(true),
      );
      final result = users.asQueryable().takeWhile_(all).toList();
      expect(result.length, 5);
    });

    test('predicate false on first element returns empty', () {
      final none = Expr.lambda(
        [Expr.param('u')],
        Expr.const_(false),
      );
      final result = users.asQueryable().takeWhile_(none).toList();
      expect(result, isEmpty);
    });

    test('chains with where_ (after)', () {
      final result = users
          .asQueryable()
          .takeWhile_(predicate)
          .where_(
            Expr.lambda(
              [Expr.param('u')],
              Expr.binary(
                '>',
                Expr.member(Expr.param('u'), 'age'),
                Expr.const_(20),
              ),
            ),
          )
          .toList();
      // takeWhile gives [Alice, Bob]. where age > 20 → [Alice].
      expect(result.map((u) => u.id), [1]);
    });

    test('argument validation: non-Lambda throws', () {
      expect(
        () => users.asQueryable().takeWhile_(Expr.const_(true)),
        throwsArgumentError,
      );
    });

    test('argument validation: multi-param Lambda throws', () {
      final bad = Expr.lambda(
        [Expr.param('u'), Expr.param('v')],
        Expr.const_(true),
      );
      expect(
        () => users.asQueryable().takeWhile_(bad),
        throwsArgumentError,
      );
    });
  });
}
