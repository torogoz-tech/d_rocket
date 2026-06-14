/// End-to-end tests for union_, intersect_, except_.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('union_', () {
    test('two non-overlapping lists', () {
      final a = [1, 2, 3].asQueryable();
      final b = [4, 5, 6].asQueryable();
      expect(a.union_(b).toList(), [1, 2, 3, 4, 5, 6]);
    });

    test('overlapping lists', () {
      final a = [1, 2, 3].asQueryable();
      final b = [3, 4, 5].asQueryable();
      expect(a.union_(b).toList(), [1, 2, 3, 4, 5]);
    });

    test('with duplicates in each', () {
      final a = [1, 1, 2, 2].asQueryable();
      final b = [2, 3, 3, 4].asQueryable();
      expect(a.union_(b).toList(), [1, 2, 3, 4]);
    });

    test('first empty', () {
      final a = <int>[].asQueryable();
      final b = [1, 2, 3].asQueryable();
      expect(a.union_(b).toList(), [1, 2, 3]);
    });

    test('second empty', () {
      final a = [1, 2, 3].asQueryable();
      final b = <int>[].asQueryable();
      expect(a.union_(b).toList(), [1, 2, 3]);
    });
  });

  group('intersect_', () {
    test('overlapping lists', () {
      final a = [1, 2, 3, 4].asQueryable();
      final b = [3, 4, 5, 6].asQueryable();
      expect(a.intersect_(b).toList(), [3, 4]);
    });

    test('no overlap returns empty', () {
      final a = [1, 2, 3].asQueryable();
      final b = [4, 5, 6].asQueryable();
      expect(a.intersect_(b).toList(), isEmpty);
    });

    test('preserves order of the first queryable', () {
      final a = [3, 1, 4, 1, 5, 9, 2, 6].asQueryable();
      final b = [1, 3, 5, 7, 9].asQueryable();
      // First 3, 1, 4, 5, 9 are in b. (1, 5 duplicate, only first kept).
      expect(a.intersect_(b).toList(), [3, 1, 5, 9]);
    });

    test('deduplicates', () {
      final a = [1, 1, 2, 2, 3, 3].asQueryable();
      final b = [1, 2, 3, 4].asQueryable();
      expect(a.intersect_(b).toList(), [1, 2, 3]);
    });
  });

  group('except_', () {
    test('basic difference', () {
      final a = [1, 2, 3, 4].asQueryable();
      final b = [3, 4].asQueryable();
      expect(a.except_(b).toList(), [1, 2]);
    });

    test('no overlap returns all of first', () {
      final a = [1, 2, 3].asQueryable();
      final b = [4, 5, 6].asQueryable();
      expect(a.except_(b).toList(), [1, 2, 3]);
    });

    test('all overlap returns empty', () {
      final a = [1, 2, 3].asQueryable();
      final b = [1, 2, 3, 4].asQueryable();
      expect(a.except_(b).toList(), isEmpty);
    });

    test('preserves order and dedups', () {
      final a = [1, 2, 1, 3, 2, 4].asQueryable();
      final b = [2, 3].asQueryable();
      // 1, 2, 1, 3, 2, 4 → not in [2,3] → 1, 1, 4. Dedup → 1, 4.
      expect(a.except_(b).toList(), [1, 4]);
    });
  });
}
