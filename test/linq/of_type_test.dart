/// End-to-end tests for the `ofType_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  // A heterogeneous source, like the kind you'd get from parsing
  // JSON into Object.
  final List<Object> mixed = [1, 'one', 2, 'two', 3, 'three', true];

  group('ofType_', () {
    test('keeps only the requested type (int)', () {
      final result = mixed.asQueryable().ofType_<int>().toList();
      expect(result, [1, 2, 3]);
    });

    test('keeps only the requested type (String)', () {
      final result = mixed.asQueryable().ofType_<String>().toList();
      expect(result, ['one', 'two', 'three']);
    });

    test('keeps only the requested type (bool)', () {
      final result = mixed.asQueryable().ofType_<bool>().toList();
      expect(result, [true]);
    });

    test('returns empty if no match', () {
      final result = mixed.asQueryable().ofType_<double>().toList();
      expect(result, isEmpty);
    });

    test('subtype matching (num matches int)', () {
      final result = mixed.asQueryable().ofType_<num>().toList();
      // num is the supertype of int. In Dart, `1 is num` is true.
      expect(result, [1, 2, 3]);
    });

    test('chains with where_', () {
      // ints that are > 1.
      final result = mixed
          .asQueryable()
          .ofType_<int>()
          .where_(
            Expr.lambda(
              [Expr.param('i')],
              Expr.binary('>', Expr.param('i'), Expr.const_(1)),
            ),
          )
          .toList();
      expect(result, [2, 3]);
    });

    test('is deferred', () {
      var iterCount = 0;
      final source = Iterable.generate(10, (i) {
        iterCount++;
        return i;
      });
      iterCount = 0;
      final q = source.asQueryable().ofType_<int>();
      expect(iterCount, 0, reason: 'ofType_ did not iterate yet');
      q.toList();
      expect(iterCount, 10);
    });
  });
}
