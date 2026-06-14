/// End-to-end tests for the `skipWhile_` LINQ operator.
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

  // age < 30: 25, 17 (yes, skip), 30 (no, stop and include).
  final predicate = Expr.lambda(
    [Expr.param('u')],
    Expr.binary(
      '<',
      Expr.member(Expr.param('u'), 'age'),
      Expr.const_(30),
    ),
  );

  group('skipWhile_', () {
    test('skips elements while predicate holds', () {
      final result = users.asQueryable().skipWhile_(predicate).toList();
      // Skips Alice(25) and Bob(17). Stops at Carol(30) — included.
      expect(result.map((u) => u.id), [3, 4, 5]);
    });

    test('predicate always true returns empty', () {
      final all = Expr.lambda(
        [Expr.param('u')],
        Expr.const_(true),
      );
      final result = users.asQueryable().skipWhile_(all).toList();
      expect(result, isEmpty);
    });

    test('predicate always false returns all', () {
      final none = Expr.lambda(
        [Expr.param('u')],
        Expr.const_(false),
      );
      final result = users.asQueryable().skipWhile_(none).toList();
      expect(result.length, 5);
    });

    test('chains with where_ (after)', () {
      // skipWhile age < 30 → [Carol(30), Dan(18), Eve(16)]
      // then filter age >= 18 → [Carol(30), Dan(18)]
      final result = users
          .asQueryable()
          .skipWhile_(predicate)
          .where_(
            Expr.lambda(
              [Expr.param('u')],
              Expr.binary(
                '>=',
                Expr.member(Expr.param('u'), 'age'),
                Expr.const_(18),
              ),
            ),
          )
          .toList();
      expect(result.map((u) => u.id), [3, 4]);
    });

    test('argument validation', () {
      expect(
        () => users.asQueryable().skipWhile_(Expr.const_(true)),
        throwsArgumentError,
      );
    });
  });
}
