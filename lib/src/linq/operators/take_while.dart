/// The `takeWhile_` LINQ operator (take elements while predicate holds).
///
/// Returns elements from the start of the queryable as long as the
/// [predicate] is `true`. Stops at the first `false` (does NOT skip
/// the false element).
///
/// In we delegate to the closure-based [Iterable.takeWhile]
/// from `dart:core`. The [Expr]-based variant lives here so that the
/// SQL translator can lower it to a `LIMIT` + `WHERE` combo.
library;

import '../enumerable_query.dart';
import '../expr.dart';
import '../i_queryable.dart';

/// The `takeWhile_` LINQ operator.
extension TakeWhileOp<T> on IQueryable<T> {
  /// Returns the prefix of the source where [predicate] is true.
  ///
  /// The [predicate] must be a single-parameter [LambdaExpr].
  ///
  /// Example:
  ///
  /// ```dart
  /// // Take elements while age is < 30.
  /// final young = users.asQueryable.takeWhile_(
  /// Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.binary('<',
  /// Expr.member(Expr.param('u'), 'age'),
  /// Expr.const_(30)),
  ///),
  ///).toList;
  /// ```
  IQueryable<T> takeWhile_(Expr predicate) {
    if (predicate is! LambdaExpr) {
      throw ArgumentError(
        'takeWhile_ predicate must be a LambdaExpr, got ${predicate.runtimeType}',
      );
    }
    final lambda = predicate;
    if (lambda.params.length != 1) {
      throw ArgumentError(
        'takeWhile_ predicate must take exactly 1 parameter, got '
        '${lambda.params.length}',
      );
    }
    return EnumerableQuery<T>(
      takeWhile(
          (item) => lambda.body.eval({lambda.params.first.name: item}) == true),
    );
  }
}
