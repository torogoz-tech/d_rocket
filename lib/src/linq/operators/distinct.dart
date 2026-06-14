/// The `distinct_` LINQ operator (remove duplicates).
///
/// Returns the elements of the source with duplicates removed. Two
/// elements are considered equal if they are `==` (Dart's default
/// equality). For custom equality, a `keySelector` can be provided
/// .
///
/// Implementation: materializes the source, then iterates keeping a
/// `Set` of seen keys.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

/// The `distinct_` LINQ operator.
extension DistinctOp<T> on IQueryable<T> {
  /// Returns the elements of the source with duplicates removed.
  ///
  /// Equality is determined by Dart's `==` (and `hashCode`).
  ///
  /// Example:
  ///
  /// ```dart
  /// final uniqueAges = users
  /// .asQueryable
  /// .select_`<int>`(
  /// Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'age'),
  ///),
  ///)
  /// .distinct_
  /// .toList;
  /// ```
  IQueryable<T> distinct_() {
    final seen = <T>{};
    final result = <T>[];
    for (final e in this) {
      if (seen.add(e)) result.add(e);
    }
    return EnumerableQuery<T>(result);
  }
}
