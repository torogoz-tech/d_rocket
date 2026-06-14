/// End-to-end tests for the `skip_` LINQ operator.
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

  group('skip_', () {
    test('skips the first N elements', () {
      final result = users.asQueryable().skip_(2).toList();
      expect(result.map((u) => u.id), [3, 4, 5]);
    });

    test('N == 0 returns all elements', () {
      final result = users.asQueryable().skip_(0).toList();
      expect(result.length, 5);
    });

    test('N == size returns empty', () {
      final result = users.asQueryable().skip_(5).toList();
      expect(result, isEmpty);
    });

    test('N > size returns empty', () {
      final result = users.asQueryable().skip_(100).toList();
      expect(result, isEmpty);
    });

    test('negative N throws RangeError (Dart 3.12 semantics)', () {
      // In Dart 3.12 Iterable.skip(-1) also throws RangeError,
      // matching the take_ behavior. (Earlier Dart versions were
      // lenient and returned all elements.)
      expect(
        () => users.asQueryable().skip_(-1).toList(),
        throwsA(isA<RangeError>()),
      );
    });

    test('paging: skip_ + take_', () {
      // Page 2 of size 2: skip 2, take 2.
      final result = users.asQueryable().skip_(2).take_(2).toList();
      expect(result.map((u) => u.id), [3, 4]); // Carol, Dan
    });

    test('chains with where_', () {
      // Adults, skip first.
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
          .skip_(1)
          .toList();
      // Adults are Alice(1), Carol(3), Dan(4). After skip(1): Carol(3), Dan(4).
      expect(result.map((u) => u.id), [3, 4]);
    });

    test('is deferred', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      final q = source.asQueryable().skip_(50);
      expect(iterCount, 0, reason: 'skip_ did not iterate yet');
      final r = q.toList();
      expect(r.length, 50);
      expect(iterCount, 100, reason: 'iterated 100 to skip 50');
    });
  });
}
