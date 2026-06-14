/// End-to-end tests for the `groupBy_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25),
    User(id: 2, name: 'Bob', age: 17),
    User(id: 3, name: 'Carol', age: 25),
    User(id: 4, name: 'Dave', age: 17),
    User(id: 5, name: 'Eve', age: 30),
  ];

  final byAge = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'age'),
  );

  group('groupBy_', () {
    test('groups by age', () {
      final groups =
          users.asQueryable().groupBy_<int>(keySelector: byAge).toList();
      expect(groups.length, 3);
      // Groups should be in first-occurrence order of the key.
      expect(groups.map((g) => g.key), [25, 17, 30]);
      // Group sizes.
      expect(groups[0].length, 2); // Alice, Carol
      expect(groups[1].length, 2); // Bob, Dave
      expect(groups[2].length, 1); // Eve
    });

    test('each group contains the right elements', () {
      final groups =
          users.asQueryable().groupBy_<int>(keySelector: byAge).toList();
      expect(groups[0].toList().map((u) => u.name).toSet(), {'Alice', 'Carol'});
      expect(groups[1].toList().map((u) => u.name).toSet(), {'Bob', 'Dave'});
      expect(groups[2].toList().map((u) => u.name).toList(), ['Eve']);
    });

    test('chains with where_ on the group', () {
      final groups = users
          .asQueryable()
          .groupBy_<int>(keySelector: byAge)
          .where_(
            Expr.lambda(
              [Expr.param('g')],
              Expr.binary(
                '>',
                Expr.member(Expr.param('g'), 'length'),
                Expr.const_(1),
              ),
            ),
          )
          .toList();
      // Groups with more than 1 element: 25 (2), 17 (2). Not 30 (1).
      expect(groups.map((g) => g.key), [25, 17]);
    });

    test('chains with select_ to project groups', () {
      // g => '${g.key}: ${g.length}'
      final labels = users
          .asQueryable()
          .groupBy_<int>(keySelector: byAge)
          .select_<String>(
            Expr.lambda(
              [Expr.param('g')],
              Expr.binary(
                '+',
                Expr.binary(
                  '+',
                  Expr.member(Expr.param('g'), 'key'),
                  Expr.const_(': '),
                ),
                Expr.member(Expr.param('g'), 'length'),
              ),
            ),
          )
          .toList();
      expect(labels, ['25: 2', '17: 2', '30: 1']);
    });

    test('empty source returns empty groups', () {
      final groups =
          <User>[].asQueryable().groupBy_<int>(keySelector: byAge).toList();
      expect(groups, isEmpty);
    });

    test('all-same-key returns one group', () {
      final sameAge = [
        User(id: 1, name: 'A', age: 25),
        User(id: 2, name: 'B', age: 25),
        User(id: 3, name: 'C', age: 25),
      ];
      final groups =
          sameAge.asQueryable().groupBy_<int>(keySelector: byAge).toList();
      expect(groups.length, 1);
      expect(groups[0].key, 25);
      expect(groups[0].length, 3);
    });

    test('invalid keySelector throws', () {
      expect(
        () => users.asQueryable().groupBy_<int>(keySelector: Expr.const_(1)),
        throwsArgumentError,
      );
    });
  });
}
