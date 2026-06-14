/// The `skipWhile_` LINQ operator (skip elements while predicate holds).
///
/// Skips elements from the start of the queryable as long as the
/// [predicate] is `true`. Returns the rest (including the first
/// element that made the predicate `false`).
library;

import '../enumerable_query.dart';
import '../expr.dart';
import '../i_queryable.dart';

/// The `skipWhile_` LINQ operator.
extension SkipWhileOp<T> on IQueryable<T> {
  /// Skips the prefix of the source where [predicate] is true.
  ///
  /// The [predicate] must be a single-parameter [LambdaExpr].
  ///
  /// Example:
  ///
  /// ```dart
  /// // Skip elements while age is < 30.
  /// final old = users.asQueryable.skipWhile_(
  /// Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.binary('<',
  /// Expr.member(Expr.param('u'), 'age'),
  /// Expr.const_(30)),
  ///),
  ///).toList;
  /// // → from Carol (age 30) onwards, including Carol
  /// ```
  IQueryable<T> skipWhile_(Expr predicate) {
    if (predicate is! LambdaExpr) {
      throw ArgumentError(
        'skipWhile_ predicate must be a LambdaExpr, got ${predicate.runtimeType}',
      );
    }
    final lambda = predicate;
    if (lambda.params.length != 1) {
      throw ArgumentError(
        'skipWhile_ predicate must take exactly 1 parameter, got '
        '${lambda.params.length}',
      );
    }
    return EnumerableQuery<T>(
      skipWhile(
          (item) => lambda.body.eval({lambda.params.first.name: item}) == true),
    );
  }
}
