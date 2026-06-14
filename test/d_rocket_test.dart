/// Integration smoke test: the first end-to-end `d_rocket` query.
///
/// This is the public-API shape that consumers will use. Keep it
/// short and readable — it doubles as documentation.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'models.dart';

void main() {
  test('end-to-end: filter users by age', () {
    final users = [
      User(id: 1, name: 'Alice', age: 25),
      User(id: 2, name: 'Bob', age: 17),
      User(id: 3, name: 'Carol', age: 30),
    ];

    // The d_rocket way: build a queryable, apply a where_, materialize.
    final adults = users
        .asQueryable()
        .where_(
          Expr.lambda(
            [Expr.param('u')],
            Expr.binary(
              '>',
              Expr.member(Expr.param('u'), 'age'),
              Expr.const_(18),
            ),
          ),
        )
        .toList();

    expect(adults.map((u) => u.name), ['Alice', 'Carol']);
  });

  test('end-to-end: chain two where_ calls', () {
    final users = [
      User(id: 1, name: 'Alice', age: 25),
      User(id: 2, name: 'Bob', age: 30),
      User(id: 3, name: 'Carol', age: 17),
    ];

    final adultsStartingWithAorC = users
        .asQueryable()
        .where_(
          Expr.lambda(
            [Expr.param('u')],
            Expr.binary(
                '>', Expr.member(Expr.param('u'), 'age'), Expr.const_(18)),
          ),
        )
        .where_(
          Expr.lambda(
            [Expr.param('u')],
            Expr.call(
              Expr.member(Expr.param('u'), 'name'),
              'startsWith',
              [Expr.const_('A')],
            ),
          ),
        )
        .toList();

    // Only Alice (25, starts with A). Carol is under 18. Bob is 30 but
    // doesn't start with A.
    expect(adultsStartingWithAorC.map((u) => u.name), ['Alice']);
  });
}
