/// Unit tests for [IQueryable] / [EnumerableQuery] / `asQueryable`.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  group('EnumerableQuery', () {
    final users = [
      User(id: 1, name: 'Alice', age: 25, email: 'a@x.com'),
      User(id: 2, name: 'Bob', age: 17, email: null),
      User(id: 3, name: 'Carol', age: 30, email: 'c@x.com'),
    ];

    test('asQueryable() lifts an Iterable', () {
      final q = users.asQueryable();
      expect(q, isA<IQueryable<User>>());
      expect(q.provider, EnumerableQueryProvider.instance);
      expect(q.expression, isNull);
      expect(q.toList(), users);
    });

    test('toList materialises the queryable', () {
      final q = users.asQueryable();
      expect(q.toList().length, 3);
    });

    test('forEach iterates in order', () {
      final q = users.asQueryable();
      final ids = <int>[];
      for (var u in q) {
        ids.add(u.id);
      }
      expect(ids, [1, 2, 3]);
    });

    test('length works', () {
      expect(users.asQueryable().length, 3);
    });

    test('isEmpty and isNotEmpty', () {
      expect(<int>[].asQueryable().isEmpty, true);
      expect(<int>[].asQueryable().isNotEmpty, false);
      expect([1].asQueryable().isEmpty, false);
      expect([1].asQueryable().isNotEmpty, true);
    });

    test('first and last', () {
      expect(users.asQueryable().first.id, 1);
      expect(users.asQueryable().last.id, 3);
    });

    test('is a lazy Iterable (no work until iterated)', () {
      // We can't directly observe laziness, but toList/toSet work.
      final q = users.asQueryable();
      expect(q.toSet().length, 3);
    });
  });

  group('EnumerableQueryProvider', () {
    test('is a singleton', () {
      expect(
        EnumerableQueryProvider.instance,
        same(EnumerableQueryProvider.instance),
      );
    });

    test('createQuery throws (Fase 1.1 limitation)', () {
      expect(
        () => EnumerableQueryProvider.instance.createQuery<User>(
          Expr.lambda([Expr.param('u')], Expr.const_(true)),
        ),
        throwsUnsupportedError,
      );
    });

    test('execute throws (Fase 1.1 limitation)', () {
      expect(
        () => EnumerableQueryProvider.instance.execute<int>(
          Expr.lambda([Expr.param('u')], Expr.const_(1)),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
