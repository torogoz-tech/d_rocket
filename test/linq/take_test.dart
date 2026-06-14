/// End-to-end tests for the `take_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25),
    User(id: 2, name: 'Bob', age: 17),
    User(id: 3, name: 'Carol', age: 30),
    User(id: 4, name: 'Dan', age: 40),
    User(id: 5, name: 'Eve', age: 16),
  ];

  group('take_', () {
    test('returns the first N elements', () {
      final result = users.asQueryable().take_(3).toList();
      expect(result.map((u) => u.id), [1, 2, 3]);
    });

    test('N == 0 returns empty', () {
      final result = users.asQueryable().take_(0).toList();
      expect(result, isEmpty);
    });

    test('N > size returns all elements', () {
      final result = users.asQueryable().take_(100).toList();
      expect(result.length, 5);
      expect(result.first.id, 1);
      expect(result.last.id, 5);
    });

    test('N == size returns all elements', () {
      final result = users.asQueryable().take_(5).toList();
      expect(result.length, 5);
    });

    test('negative N throws RangeError', () {
      // Mirrors Dart's Iterable.take / C# Take semantics: negative
      // counts are an error, not "return empty".
      expect(
        () => users.asQueryable().take_(-1).toList(),
        throwsA(isA<RangeError>()),
      );
    });

    test('chains with where_', () {
      // Adults, take first 2.
      final result = users
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
          .take_(2)
          .toList();
      expect(result.map((u) => u.id), [1, 3]); // Alice, Carol
    });

    test('chains with select_', () {
      final result = users
          .asQueryable()
          .take_(2)
          .select_<String>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'name'),
            ),
          )
          .toList();
      expect(result, ['Alice', 'Bob']);
    });

    test('is deferred (does not iterate until terminal)', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      final q = source.asQueryable().take_(5);
      expect(iterCount, 0, reason: 'take_ did not iterate yet');
      final r = q.toList();
      expect(r.length, 5);
      expect(iterCount, 5, reason: 'toList iterated 5 elements');
    });
  });
}
