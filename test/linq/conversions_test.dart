/// End-to-end tests for the conversion LINQ operators.
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

  group('toList_', () {
    test('materializes to a list', () {
      final result = users.asQueryable().toList_();
      expect(result, isA<List<User>>());
      expect(result.length, 3);
    });

    test('after where_', () {
      final result = users
          .asQueryable()
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
          .toList_();
      expect(result.map((u) => u.id), [1, 3]);
    });
  });

  group('toSet_', () {
    test('materializes to a set', () {
      final result = [1, 2, 2, 3].asQueryable().toSet_();
      expect(result, isA<Set<int>>());
      expect(result, {1, 2, 3});
    });
  });

  group('toMap_', () {
    test('builds a map by key selector', () {
      final byId = users.asQueryable().toMap_<int>(
            keySelector: Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'id'),
            ),
          );
      expect(byId, isA<Map<int, User>>());
      expect(byId.keys, [1, 2, 3]);
      expect(byId[2]?.name, 'Bob');
    });

    test('duplicate keys throw', () {
      // To force a duplicate, build from a list of users with same id.
      final source = [
        User(id: 1, name: 'A', age: 25),
        User(id: 1, name: 'B', age: 30),
      ].asQueryable();
      expect(
        () => source.toMap_<int>(
          keySelector: Expr.lambda(
            [Expr.param('u')],
            Expr.member(Expr.param('u'), 'id'),
          ),
        ),
        throwsStateError,
      );
    });

    test('invalid keySelector throws', () {
      expect(
        () => users.asQueryable().toMap_<int>(keySelector: Expr.const_(1)),
        throwsArgumentError,
      );
    });
  });

  group('asEnumerable_', () {
    test('returns an Iterable', () {
      final result = users.asQueryable().asEnumerable_();
      expect(result, isA<Iterable<User>>());
      expect(result.toList().length, 3);
    });
  });

  group('cast_', () {
    test('cast from Object to int', () {
      final List<Object> mixed = [1, 2, 3];
      final result = mixed.asQueryable().cast_<int>().toList();
      expect(result, [1, 2, 3]);
    });

    test('cast mismatch throws', () {
      final List<Object> mixed = [1, 'two', 3];
      expect(
        () => mixed.asQueryable().cast_<int>().toList(),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
