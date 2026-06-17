/// The `selectMany_` LINQ operator (one-to-many projection +
/// flattening).
///
/// `selectMany_<TCollection, TResult>` (with `collectionSelector`
/// and an optional `[resultSelector]`) projects each element of the
/// queryable
/// to an [Iterable] (the "inner" collection) and flattens
/// the result. With an optional [resultSelector], each pair
/// of (outer, inner) is combined into a final result.
///
/// The operator is the LINQ equivalent of `flatMap`. A queryable
/// of `Order` (where each `Order` has a `List<LineItem> items`)
/// can become a queryable of `LineItem` via
/// `selectMany_((o) => o.items)`.
///
/// The closure-translator support for `selectMany_` is the same
/// as for `select_`: hand-rolled recursive-descent emits the
/// `Expr.lambda(...)` form when the user writes a Dart closure
/// (e.g. `q.selectMany_((o) => o.items)`). The runtime does
/// not depend on the translator; both forms work.
///
/// SQL push-down is **not** implemented in this version: the
/// operator works in the in-memory provider (the
/// [EnumerableQueryProvider]) and is a no-op for the
/// `TranslatableProvider` (it returns a query that the SQL
/// translator will treat as an in-memory operation). The
/// push-down is a 1.3.0 candidate.
library;

import '../expr.dart';
import '../i_query_provider.dart';
import '../i_queryable.dart';

/// The `selectMany_` LINQ operator.
extension SelectManyOp<T> on IQueryable<T> {
  /// Projects each element into a collection and
  /// flattens the result.
  ///
  /// The [collectionSelector] is a single-parameter
  /// [LambdaExpr] whose body must return an [Iterable]
  /// (the inner collection for that outer element).
  ///
  /// The optional [resultSelector] is a two-parameter
  /// [LambdaExpr] (outer, inner) that maps each pair to
  /// the final result type. When omitted, the inner
  /// element type is used.
  ///
  /// Example:
  ///
  /// ```dart
  /// final allItems = orders
  /// .asQueryable
  /// .selectMany_`<LineItem, LineItem>`(
  /// Expr.lambda(
  /// [Expr.param('o')],
  /// Expr.member(Expr.param('o'), 'items'),
  ///))
  /// .toList;
  /// // → flat List<LineItem> with every line item
  /// //   from every order
  /// ```
  IQueryable<TResult> selectMany_<TCollection, TResult>(
    Expr collectionSelector, {
    Expr? resultSelector,
  }) {
    if (collectionSelector is! LambdaExpr) {
      throw ArgumentError(
        'selectMany_ collectionSelector must be a LambdaExpr, '
        'got ${collectionSelector.runtimeType}',
      );
    }
    final cs = collectionSelector;
    if (cs.params.length != 1) {
      throw ArgumentError(
        'selectMany_ collectionSelector must take exactly 1 '
        'parameter, got ${cs.params.length}',
      );
    }
    LambdaExpr? rs;
    if (resultSelector != null) {
      if (resultSelector is! LambdaExpr) {
        throw ArgumentError(
          'selectMany_ resultSelector must be a LambdaExpr, '
          'got ${resultSelector.runtimeType}',
        );
      }
      rs = resultSelector;
      if (rs.params.length != 2) {
        throw ArgumentError(
          'selectMany_ resultSelector must take exactly 2 '
          'parameters (outer, inner), got ${rs.params.length}',
        );
      }
    }
    return _SelectManyEnumerableQuery<T, TCollection, TResult>(
      this,
      cs,
      rs,
    );
  }
}

class _SelectManyEnumerableQuery<T, TCollection, TResult>
    extends IQueryable<TResult> {
  final IQueryable<T> _source;
  final LambdaExpr _collectionSelector;
  final LambdaExpr? _resultSelector;

  _SelectManyEnumerableQuery(
    this._source,
    this._collectionSelector,
    this._resultSelector,
  );

  @override
  IQueryProvider get provider => _source.provider;

  @override
  Expr? get expression => null; // built-up expression tree; Fase 2+.

  @override
  Iterator<TResult> get iterator {
    final csParam = _collectionSelector.params.first.name;
    final csBody = _collectionSelector.body;
    final rs = _resultSelector;
    final rsOuterParam = rs?.params[0].name;
    final rsInnerParam = rs?.params[1].name;
    final rsBody = rs?.body;

    return _FlatSelectManyIterator<T, TResult>(
      _source.iterator,
      csParam,
      csBody,
      rs,
      rsOuterParam,
      rsInnerParam,
      rsBody,
    );
  }
}

class _FlatSelectManyIterator<T, TResult> implements Iterator<TResult> {
  _FlatSelectManyIterator(
    this._outer,
    this._csParam,
    this._csBody,
    this._rs,
    this._rsOuterParam,
    this._rsInnerParam,
    this._rsBody,
  );

  final Iterator<T> _outer;
  final String _csParam;
  final Expr _csBody;
  final LambdaExpr? _rs;
  final String? _rsOuterParam;
  final String? _rsInnerParam;
  final Expr? _rsBody;

  Iterator<dynamic> _inner = const <dynamic>[].iterator;
  TResult? _current;

  @override
  TResult get current => _current as TResult;

  @override
  bool moveNext() {
    while (true) {
      if (_inner.moveNext()) {
        if (_rs != null) {
          _current = _rsBody!.eval(<String, Object?>{
            _rsOuterParam!: _outer.current,
            _rsInnerParam!: _inner.current,
          }) as TResult;
        } else {
          _current = _inner.current as TResult;
        }
        return true;
      }
      if (!_outer.moveNext()) {
        return false;
      }
      final Object? innerCollection =
          _csBody.eval(<String, Object?>{_csParam: _outer.current});
      if (innerCollection is! Iterable) {
        throw StateError(
          'selectMany_ collectionSelector must return an Iterable, '
          'got ${innerCollection.runtimeType}',
        );
      }
      _inner = innerCollection.iterator;
    }
  }
}
