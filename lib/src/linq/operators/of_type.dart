/// The `ofType_` LINQ operator (filter by runtime type).
///
/// `ofType_<TResult>` returns the elements that are assignable to
/// `TResult` according to [Type] semantics. Useful for heterogeneous
/// sources (e.g. a `List<Object>` containing both `int` and `String`).
///
/// In this is purely a runtime check. In the type
/// filter would be expressed as a `WHERE` clause with a SQL cast.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

/// The `ofType_` LINQ operator.
extension OfTypeOp<T> on IQueryable<T> {
  /// Returns the elements whose runtime type is a subtype of [TResult].
  ///
  /// Example:
  ///
  /// ```dart
  /// final ints = mixed.asQueryable.ofType_`<int>`.toList;
  /// // → only the int elements
  /// ```
  IQueryable<TResult> ofType_<TResult>() =>
      EnumerableQuery<TResult>(where((e) => e is TResult).cast<TResult>());
}
