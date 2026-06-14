/// End-to-end tests for the `select_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25, email: 'a@x.com'),
    User(id: 2, name: 'Bob', age: 17, email: null),
    User(id: 3, name: 'Carol', age: 30, email: 'c@x.com'),
  ];

  group('select_ — basic projection', () {
    test('projects to a field', () {
      final names = users
          .asQueryable()
          .select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'name'),
            ),
          )
          .toList();
      expect(names, ['Alice', 'Bob', 'Carol']);
    });

    test('projects to a computed value', () {
      // u => u.name + '!'
      final labels = users
          .asQueryable()
          .select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.binary(
                '+',
                Expr.member(Expr.param('u'), 'name'),
                Expr.const_('!'),
              ),
            ),
          )
          .toList();
      expect(labels, ['Alice!', 'Bob!', 'Carol!']);
    });

    test('changes element type', () {
      final ages = users
          .asQueryable()
          .select_<int>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'age'),
            ),
          )
          .toList();
      expect(ages, [25, 17, 30]);
    });
  });

  group('select_ — chaining with where_', () {
    test('filter then project', () {
      // Adults (age > 18) → name
      final adultNames = users
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
          .select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'name'),
            ),
          )
          .toList();
      expect(adultNames, ['Alice', 'Carol']);
    });

    test('project then filter', () {
      // Name → filter by startsWith
      final namesStartingWithA = users
          .asQueryable()
          .select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'name'),
            ),
          )
          .where_(
            Expr.lambda(
              [Expr.param('n')],
              Expr.call(
                Expr.param('n'),
                'startsWith',
                [Expr.const_('A')],
              ),
            ),
          )
          .toList();
      expect(namesStartingWithA, ['Alice']);
    });
  });

  group('select_ — argument validation', () {
    test('non-LambdaExpr selector throws', () {
      expect(
        () => users.asQueryable().select_<String>(Expr.const_('hello')),
        throwsArgumentError,
      );
    });

    test('multi-parameter Lambda throws', () {
      final bad = Expr.lambda(
        [Expr.param('u'), Expr.param('v')],
        Expr.const_('x'),
      );
      expect(
        () => users.asQueryable().select_<String>(bad),
        throwsArgumentError,
      );
    });
  });

  group('select_ — deferred execution', () {
    test('does not project until a terminal operator', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return User(id: i, name: 'n$i', age: 20 + (i % 50));
      });
      iterCount = 0;
      final q = source.asQueryable().select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'name'),
            ),
          );
      expect(iterCount, 0, reason: 'select_ did not iterate yet');
      final r = q.toList();
      expect(r.length, 100);
      expect(iterCount, 100, reason: 'toList iterated all 100');
    });
  });
}
