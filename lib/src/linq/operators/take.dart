/// The `take_` LINQ operator (return the first [count] elements).
///
/// In we delegate to the closure-based [Iterable.take] from
/// `dart:core`. In (SQLite) this will be translated to a
/// `LIMIT n` clause.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

/// The `take_` LINQ operator.
extension TakeOp<T> on IQueryable<T> {
  /// Returns a queryable containing at most the first [count] elements.
  ///
  /// Example:
  ///
  /// ```dart
  /// final first3 = users.asQueryable.take_(3).toList;
  /// // → first 3 users (in source order)
  /// ```
  ///
  /// If [count] is negative, the result is empty. If [count] is
  /// greater than the number of elements, all elements are returned.
  IQueryable<T> take_(int count) => EnumerableQuery<T>(take(count));
}
