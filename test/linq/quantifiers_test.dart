/// End-to-end tests for any_, all_, contains_.
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

  final isAdult = Expr.lambda(
    [Expr.param('u')],
    Expr.binary(
      '>=',
      Expr.member(Expr.param('u'), 'age'),
      Expr.const_(18),
    ),
  );

  group('any_', () {
    test('without predicate: empty source', () {
      expect(<int>[].asQueryable().any_(), false);
    });

    test('without predicate: non-empty source', () {
      expect(users.asQueryable().any_(), true);
    });

    test('with predicate: at least one match', () {
      expect(users.asQueryable().any_(where: isAdult), true);
    });

    test('with predicate: no match', () {
      final isOld = Expr.lambda(
        [Expr.param('u')],
        Expr.binary('>', Expr.member(Expr.param('u'), 'age'), Expr.const_(100)),
      );
      expect(users.asQueryable().any_(where: isOld), false);
    });

    test('short-circuits on first match', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return User(id: i, name: 'n$i', age: 25);
      });
      iterCount = 0;
      // First user matches → no further iteration.
      final result = source.asQueryable().any_(where: isAdult);
      expect(result, true);
      expect(iterCount, 1, reason: 'any_ short-circuits on first match');
    });

    test('invalid predicate throws', () {
      expect(
        () => users.asQueryable().any_(where: Expr.const_(true)),
        throwsArgumentError,
      );
    });
  });

  group('all_', () {
    test('empty source: vacuously true', () {
      expect(<User>[].asQueryable().all_(isAdult), true);
    });

    test('all match', () {
      final allAdults = [
        User(id: 1, name: 'A', age: 30),
        User(id: 2, name: 'B', age: 25),
      ].asQueryable();
      expect(allAdults.all_(isAdult), true);
    });

    test('some do not match', () {
      expect(users.asQueryable().all_(isAdult), false);
    });

    test('none match', () {
      final allYoung = [
        User(id: 1, name: 'A', age: 5),
        User(id: 2, name: 'B', age: 8),
      ].asQueryable();
      expect(allYoung.all_(isAdult), false);
    });

    test('short-circuits on first non-match', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return User(id: i, name: 'n$i', age: i); // first 18 are NOT adults.
      });
      iterCount = 0;
      final result = source.asQueryable().all_(isAdult);
      expect(result, false);
      // i=0 is not adult → short-circuits at i=0.
      // But wait, we need to check the first non-match. Age 0 is not adult.
      // So iterCount should be 1 (evaluated age 0, found non-match).
      expect(iterCount, 1, reason: 'all_ short-circuits on first non-match');
    });
  });

  group('contains_', () {
    test('value present', () {
      expect([1, 2, 3].asQueryable().contains_(2), true);
    });

    test('value absent', () {
      expect([1, 2, 3].asQueryable().contains_(99), false);
    });

    test('empty source', () {
      expect(<int>[].asQueryable().contains_(1), false);
    });

    test('uses == / hashCode', () {
      // Two Users with same id are considered different (default
      // equality is identity). So this returns false.
      final a = User(id: 1, name: 'A', age: 25);
      final b = User(id: 1, name: 'A', age: 25);
      expect([a].asQueryable().contains_(b), false);
    });

    test('short-circuits on first match', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      expect(source.asQueryable().contains_(50), true);
      expect(iterCount, 51, reason: '50 is the 51st element (0-indexed)');
    });
  });
}
