/// The `where_` LINQ operator (filter).
///
/// `where_` is suffixed with an underscore to avoid clashing with
/// [Iterable.where] from `dart:core`. The user-facing name will be
/// `where` once Dart supports better namespace separation (or once
/// we move to a separate imports model).
///
/// In `where_` accepts a [LambdaExpr] with exactly one
/// parameter. The body is evaluated against each element; elements
/// for which it returns `true` are kept.
///
/// In (SQLite), the same [Expr] tree is translated to a SQL
/// `WHERE` clause instead of being evaluated in memory.
library;

import '../expr.dart';
import '../i_query_provider.dart';
import '../i_queryable.dart';
// (unused: ../enumerable_query.dart)

/// The `where_` LINQ operator.
extension WhereOp<T> on IQueryable<T> {
  /// Filters the queryable to elements for which [predicate] returns
  /// `true`. The [predicate] must be a single-parameter [LambdaExpr].
  ///
  /// Example:
  ///
  /// ```dart
  /// final adults = users
  /// .asQueryable
  /// .where_(Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.binary('>',
  /// Expr.member(Expr.param('u'), 'age'),
  /// Expr.const_(18)),
  ///))
  /// .toList;
  /// ```
  IQueryable<T> where_(Expr predicate) {
    if (predicate is! LambdaExpr) {
      throw ArgumentError(
        'where_ predicate must be a LambdaExpr, got ${predicate.runtimeType}',
      );
    }
    final lambda = predicate;
    if (lambda.params.length != 1) {
      throw ArgumentError(
        'where_ predicate must take exactly 1 parameter, got '
        '${lambda.params.length}',
      );
    }
    return _FilteredEnumerableQuery<T>(this, lambda);
  }
}

class _FilteredEnumerableQuery<T> extends IQueryable<T> {
  final IQueryable<T> _source;
  final LambdaExpr _predicate;

  _FilteredEnumerableQuery(this._source, this._predicate);

  @override
  IQueryProvider get provider => _source.provider;

  @override
  Expr? get expression => null; // built-up expression tree; Fase 2+.

  @override
  Iterator<T> get iterator {
    final paramName = _predicate.params.first.name;
    final body = _predicate.body;
    return _source
        .where((item) => body.eval({paramName: item}) == true)
        .iterator;
  }
}
