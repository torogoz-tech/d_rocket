/// The `skip_` LINQ operator (skip the first [count] elements).
///
/// In we delegate to the closure-based [Iterable.skip] from
/// `dart:core`. In (SQLite) this will be translated to an
/// `OFFSET n` clause.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

/// The `skip_` LINQ operator.
extension SkipOp<T> on IQueryable<T> {
  /// Returns a queryable that skips the first [count] elements.
  ///
  /// Example:
  ///
  /// ```dart
  /// final from4th = users.asQueryable.skip_(3).toList;
  /// // → 4th user onwards
  /// ```
  ///
  /// If [count] is non-positive, all elements are returned. If
  /// [count] is greater than the number of elements, the result is
  /// empty.
  IQueryable<T> skip_(int count) => EnumerableQuery<T>(skip(count));
}
