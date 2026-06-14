/// End-to-end tests for the `orderBy_` family of LINQ operators.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Charlie', age: 30),
    User(id: 2, name: 'Alice', age: 25),
    User(id: 3, name: 'Bob', age: 30),
    User(id: 4, name: 'Dave', age: 25),
    User(id: 5, name: 'Eve', age: 17),
  ];

  final byAge = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'age'),
  );
  final byName = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'name'),
  );

  group('orderBy_', () {
    test('sorts ascending by age', () {
      final result = users.asQueryable().orderBy_(byAge).toList();
      expect(result.map((u) => u.id), [5, 2, 4, 1, 3]);
    });

    test('stable sort: equal ages preserve insertion order', () {
      final result = users.asQueryable().orderBy_(byAge).toList();
      // Two 25s: Alice(2) then Dave(4). Two 30s: Charlie(1) then Bob(3).
      expect(result.map((u) => u.id), [5, 2, 4, 1, 3]);
    });
  });

  group('orderByDescending_', () {
    test('sorts descending by age', () {
      final result = users.asQueryable().orderByDescending_(byAge).toList();
      expect(result.map((u) => u.id), [1, 3, 2, 4, 5]);
    });
  });

  group('orderBy_ + thenBy_', () {
    test('secondary ascending sort', () {
      final result =
          users.asQueryable().orderBy_(byAge).thenBy_(byName).toList();
      // Age groups: 17 (Eve), 25 (Alice, Dave), 30 (Bob, Charlie).
      // Within each age, ascending by name.
      expect(result.map((u) => u.id), [5, 2, 4, 3, 1]);
    });

    test('orderByDescending + thenBy_', () {
      final result = users
          .asQueryable()
          .orderByDescending_(byAge)
          .thenBy_(byName)
          .toList();
      // Age groups descending: 30 (Bob, Charlie), 25 (Alice, Dave), 17 (Eve).
      expect(result.map((u) => u.id), [3, 1, 2, 4, 5]);
    });

    test('orderBy_ + thenByDescending_', () {
      final result = users
          .asQueryable()
          .orderBy_(byAge)
          .thenByDescending_(byName)
          .toList();
      // Age ascending, within each age, name descending.
      expect(result.map((u) => u.id), [5, 4, 2, 1, 3]);
    });
  });

  group('orderBy_ — error cases', () {
    test('thenBy_ without orderBy_ throws', () {
      expect(
        () => users.asQueryable().thenBy_(byName).toList(),
        throwsStateError,
      );
    });

    test('non-Lambda keySelector throws', () {
      expect(
        () => users.asQueryable().orderBy_(Expr.const_(1)),
        throwsArgumentError,
      );
    });

    test('multi-parameter keySelector throws', () {
      final bad = Expr.lambda(
        [Expr.param('u'), Expr.param('v')],
        Expr.const_(1),
      );
      expect(
        () => users.asQueryable().orderBy_(bad),
        throwsArgumentError,
      );
    });
  });

  group('orderBy_ — chains with where_', () {
    test('filter then sort', () {
      final result = users
          .asQueryable()
          .where_(
            Expr.lambda(
              [Expr.param('u')],
              Expr.binary(
                '>=',
                Expr.member(Expr.param('u'), 'age'),
                Expr.const_(25),
              ),
            ),
          )
          .orderBy_(byName)
          .toList();
      // age >= 25: Charlie(1), Alice(2), Bob(3), Dave(4). By name: Alice, Bob, Charlie, Dave.
      expect(result.map((u) => u.id), [2, 3, 1, 4]);
    });
  });
}
