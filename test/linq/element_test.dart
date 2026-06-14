/// End-to-end tests for first_, firstOrDefault_, single_, singleOrDefault_,
/// elementAt_, elementAtOrDefault_.
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

  group('first_', () {
    test('first element of non-empty source', () {
      expect(users.asQueryable().first_().id, 1);
    });

    test('with predicate', () {
      expect(users.asQueryable().first_(where: isAdult).id, 1); // Alice
    });

    test('empty source throws', () {
      expect(
        () => <User>[].asQueryable().first_(),
        throwsStateError,
      );
    });

    test('predicate with no match throws', () {
      final allYoung = Expr.lambda(
        [Expr.param('u')],
        Expr.binary('<', Expr.member(Expr.param('u'), 'age'), Expr.const_(0)),
      );
      expect(
        () => users.asQueryable().first_(where: allYoung),
        throwsStateError,
      );
    });

    test('short-circuits on first match', () {
      var iterCount = 0;
      final source = Iterable.generate(100, (i) {
        iterCount++;
        return User(id: i, name: 'n$i', age: 25);
      });
      iterCount = 0;
      users.asQueryable().first_(where: isAdult); // local copy used
      // Reset: the test above mutated `iterCount` but the result is
      // about the *queriable* (not the same source). Use the new one.
      iterCount = 0;
      source.asQueryable().first_(where: isAdult);
      expect(iterCount, 1, reason: 'first_ short-circuits on first match');
    });
  });

  group('firstOrDefault_', () {
    test('first element', () {
      expect(users.asQueryable().firstOrDefault_()?.id, 1);
    });

    test('empty source returns null', () {
      expect(<User>[].asQueryable().firstOrDefault_(), isNull);
    });

    test('with predicate', () {
      expect(users.asQueryable().firstOrDefault_(where: isAdult)?.id, 1);
    });

    test('predicate with no match returns null', () {
      final allYoung = Expr.lambda(
        [Expr.param('u')],
        Expr.binary('<', Expr.member(Expr.param('u'), 'age'), Expr.const_(0)),
      );
      expect(users.asQueryable().firstOrDefault_(where: allYoung), isNull);
    });
  });

  group('single_', () {
    test('exactly one element', () {
      expect([User(id: 1, name: 'A', age: 25)].asQueryable().single_().id, 1);
    });

    test('more than one throws', () {
      expect(
        () => users.asQueryable().single_(),
        throwsStateError,
      );
    });

    test('empty source throws', () {
      expect(
        () => <User>[].asQueryable().single_(),
        throwsStateError,
      );
    });

    test('with predicate: exactly one match', () {
      final onlyBob = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
            '==', Expr.member(Expr.param('u'), 'name'), Expr.const_('Bob')),
      );
      expect(users.asQueryable().single_(where: onlyBob).id, 2);
    });

    test('with predicate: zero matches throws', () {
      final noneMatch = Expr.lambda(
        [Expr.param('u')],
        Expr.const_(false),
      );
      expect(
        () => users.asQueryable().single_(where: noneMatch),
        throwsStateError,
      );
    });
  });

  group('singleOrDefault_', () {
    test('exactly one element', () {
      expect(
        [User(id: 1, name: 'A', age: 25)].asQueryable().singleOrDefault_()?.id,
        1,
      );
    });

    test('zero returns null', () {
      expect(<User>[].asQueryable().singleOrDefault_(), isNull);
    });

    test('more than one throws', () {
      expect(
        () => users.asQueryable().singleOrDefault_(),
        throwsStateError,
      );
    });
  });

  group('elementAt_', () {
    test('valid index', () {
      expect(users.asQueryable().elementAt_(1).id, 2);
    });

    test('index 0', () {
      expect(users.asQueryable().elementAt_(0).id, 1);
    });

    test('out of range throws', () {
      expect(
        () => users.asQueryable().elementAt_(99),
        throwsA(isA<RangeError>()),
      );
    });

    test('negative index throws', () {
      expect(
        () => users.asQueryable().elementAt_(-1),
        throwsA(isA<RangeError>()),
      );
    });
  });

  group('elementAtOrDefault_', () {
    test('valid index', () {
      expect(users.asQueryable().elementAtOrDefault_(1)?.id, 2);
    });

    test('out of range returns null', () {
      expect(users.asQueryable().elementAtOrDefault_(99), isNull);
    });

    test('negative index returns null', () {
      expect(users.asQueryable().elementAtOrDefault_(-1), isNull);
    });
  });
}
