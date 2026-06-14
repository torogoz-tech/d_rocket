/// The `concat_` LINQ operator (concatenate two queryables).
///
/// Returns the elements of [this] followed by the elements of [other].
/// Both queryables must have the same element type.
///
/// In (SQLite) `concat_` translates to a `UNION ALL`.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

/// The `concat_` LINQ operator.
extension ConcatOp<T> on IQueryable<T> {
  /// Concatenates this queryable with [other].
  ///
  /// Example:
  ///
  /// ```dart
  /// final active = activeUsers.asQueryable;
  /// final inactive = inactiveUsers.asQueryable;
  /// final everyone = active.concat_(inactive).toList;
  /// ```
  IQueryable<T> concat_(IQueryable<T> other) {
    final first = this;
    return EnumerableQuery<T>(_concatGen(first, other));
  }
}

Iterable<T> _concatGen<T>(Iterable<T> a, Iterable<T> b) sync* {
  yield* a;
  yield* b;
}
