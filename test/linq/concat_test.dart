/// End-to-end tests for the `concat_` LINQ operator.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('concat_', () {
    test('concatenates two lists', () {
      final a = [1, 2, 3].asQueryable();
      final b = [4, 5, 6].asQueryable();
      expect(a.concat_(b).toList(), [1, 2, 3, 4, 5, 6]);
    });

    test('first empty returns the second', () {
      final a = <int>[].asQueryable();
      final b = [1, 2, 3].asQueryable();
      expect(a.concat_(b).toList(), [1, 2, 3]);
    });

    test('second empty returns the first', () {
      final a = [1, 2, 3].asQueryable();
      final b = <int>[].asQueryable();
      expect(a.concat_(b).toList(), [1, 2, 3]);
    });

    test('both empty returns empty', () {
      final a = <int>[].asQueryable();
      final b = <int>[].asQueryable();
      expect(a.concat_(b).toList(), isEmpty);
    });

    test('preserves order (does NOT dedup)', () {
      // concat_ keeps duplicates; for dedup use distinct_.
      final a = [1, 2, 3].asQueryable();
      final b = [2, 3, 4].asQueryable();
      expect(a.concat_(b).toList(), [1, 2, 3, 2, 3, 4]);
    });

    test('chains with where_', () {
      final a = [1, 2, 3, 4, 5].asQueryable();
      final b = [6, 7, 8, 9, 10].asQueryable();
      // Filter: only evens. After concat: [2, 4, 6, 8, 10].
      final result = a
          .concat_(b)
          .where_(
            Expr.lambda(
              [Expr.param('n')],
              Expr.binary(
                '==',
                Expr.binary('%', Expr.param('n'), Expr.const_(2)),
                Expr.const_(0),
              ),
            ),
          )
          .toList();
      expect(result, [2, 4, 6, 8, 10]);
    });

    test('is deferred until terminal', () {
      var aCount = 0;
      var bCount = 0;
      final a = Iterable.generate(3, (i) {
        aCount++;
        return i + 1;
      }).asQueryable();
      final b = Iterable.generate(3, (i) {
        bCount++;
        return i + 4;
      }).asQueryable();
      aCount = 0;
      bCount = 0;
      final q = a.concat_(b);
      expect(aCount, 0, reason: 'first source not yet iterated');
      expect(bCount, 0, reason: 'second source not yet iterated');
      q.toList();
      expect(aCount, 3);
      expect(bCount, 3);
    });
  });
}
