/// End-to-end tests for the `distinct_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('distinct_', () {
    test('removes duplicate ints', () {
      final result =
          [1, 2, 2, 3, 1, 4, 3, 5].asQueryable().distinct_().toList();
      expect(result, [1, 2, 3, 4, 5]);
    });

    test('preserves first occurrence order', () {
      final result = [3, 1, 2, 1, 3, 2].asQueryable().distinct_().toList();
      expect(result, [3, 1, 2]);
    });

    test('empty source returns empty', () {
      final result = <int>[].asQueryable().distinct_().toList();
      expect(result, isEmpty);
    });

    test('all duplicates collapse to one', () {
      final result = [7, 7, 7, 7].asQueryable().distinct_().toList();
      expect(result, [7]);
    });

    test('chains with select_ to dedup a derived sequence', () {
      // Ages: 25, 17, 30, 17, 25 → distinct: 25, 17, 30.
      final users = [
        _User(1, 25),
        _User(2, 17),
        _User(3, 30),
        _User(4, 17),
        _User(5, 25),
      ];
      final ages = users
          .asQueryable()
          .select_<int>(
            Expr.lambda(
              [Expr.param('u')],
              Expr.member(Expr.param('u'), 'age'),
            ),
          )
          .distinct_()
          .toList();
      expect(ages, [25, 17, 30]);
    });

    test('distinct_ of strings is case-sensitive', () {
      final result =
          ['a', 'A', 'b', 'a', 'B'].asQueryable().distinct_().toList();
      expect(result, ['a', 'A', 'b', 'B']);
    });
  });
}

class _User implements RecordLike {
  _User(this.id, this.age);
  final int id;
  final int age;
  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'age' => age,
        _ => null,
      };
}
