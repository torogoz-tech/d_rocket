/// The `select_` LINQ operator (projection).
///
/// `select_<TResult>(selector)` projects each element of the queryable
/// to a new form. The [selector] is a single-parameter [LambdaExpr]
/// whose body is evaluated against each source element and whose
/// return value becomes the next element.
///
/// The projection can change the element type: a queryable of `User`
/// can become a queryable of `String`, `int`, or any other type
/// expressible in the [Expr] DSL.
library;

import '../expr.dart';
import '../i_query_provider.dart';
import '../i_queryable.dart';

/// The `select_` LINQ operator.
extension SelectOp<T> on IQueryable<T> {
  /// Projects each element into a new form.
  ///
  /// Example:
  ///
  /// ```dart
  /// final names = users
  /// .asQueryable
  /// .select_`<String>`(Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'name'),
  ///))
  /// .toList;
  /// // → ['Alice', 'Bob', 'Carol']
  /// ```
  IQueryable<TResult> select_<TResult>(Expr selector) {
    if (selector is! LambdaExpr) {
      throw ArgumentError(
        'select_ selector must be a LambdaExpr, got ${selector.runtimeType}',
      );
    }
    final lambda = selector;
    if (lambda.params.length != 1) {
      throw ArgumentError(
        'select_ selector must take exactly 1 parameter, got '
        '${lambda.params.length}',
      );
    }
    return _ProjectedEnumerableQuery<T, TResult>(this, lambda);
  }
}

class _ProjectedEnumerableQuery<T, TResult> extends IQueryable<TResult> {
  final IQueryable<T> _source;
  final LambdaExpr _selector;

  _ProjectedEnumerableQuery(this._source, this._selector);

  @override
  IQueryProvider get provider => _source.provider;

  @override
  Expr? get expression => null; // built-up expression tree; Fase 2+.

  @override
  Iterator<TResult> get iterator {
    final paramName = _selector.params.first.name;
    final body = _selector.body;
    return _source
        .map((item) => body.eval({paramName: item}) as TResult)
        .iterator;
  }
}
