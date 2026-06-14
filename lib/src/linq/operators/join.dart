/// The `join_` and `groupJoin_` LINQ operators (relational joins).
///
/// * `join_(inner, outerKey, innerKey, resultSelector)` — INNER JOIN.
/// Produces a flat sequence of joined pairs.
/// * `groupJoin_(inner, outerKey, innerKey, resultSelector)` — LEFT
/// OUTER JOIN grouped by outer key. Each outer element is paired
/// with the list of matching inner elements (possibly empty).
///
/// Both are terminal-ish: they materialize the inner sequence
/// once (for an index lookup), then stream the joined results.
library;

import '../expr.dart';
import '../i_query_provider.dart';
import '../i_queryable.dart';

extension JoinOp<TOuter> on IQueryable<TOuter> {
  /// INNER JOIN: pairs each element of [this] with elements of
  /// [inner] whose key matches the outer element's key.
  ///
  /// Parameters:
  ///
  /// * [inner] — the right-hand side of the join.
  /// * [outerKeySelector] — extracts the join key from each
  /// [TOuter] element. Single-parameter [LambdaExpr].
  /// * [innerKeySelector] — extracts the join key from each
  /// [TInner] element. Single-parameter [LambdaExpr].
  /// * [resultSelector] — combines the matched outer and inner
  /// elements into the result. Two-parameter [LambdaExpr]:
  /// `(o, i) => r`.
  ///
  /// Example:
  ///
  /// ```dart
  /// // SELECT u.id, p.title
  /// // FROM users u JOIN posts p ON p.userId = u.id
  /// final pairs = users.asQueryable.join_`<User, Post, int, String>`(
  /// inner: posts.asQueryable,
  /// outerKeySelector: Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'id'),
  ///),
  /// innerKeySelector: Expr.lambda(
  /// [Expr.param('p')],
  /// Expr.member(Expr.param('p'), 'userId'),
  ///),
  /// resultSelector: Expr.lambda(
  /// [Expr.param('u'), Expr.param('p')],
  /// Expr.binary(
  /// '+',
  /// Expr.binary(
  /// '+',
  /// Expr.member(Expr.param('u'), 'name'),
  /// Expr.const_(' wrote '),
  ///),
  /// Expr.member(Expr.param('p'), 'title'),
  ///),
  ///),
  ///);
  /// ```
  IQueryable<TResult> join_<TInner, TKey, TResult>({
    required IQueryable<TInner> inner,
    required Expr outerKeySelector,
    required Expr innerKeySelector,
    required Expr resultSelector,
  }) =>
      _JoinEnumerableQuery<TOuter, TInner, TKey, TResult>(
        this,
        inner,
        _requireKey('join_', outerKeySelector),
        _requireKey('join_', innerKeySelector),
        _requireResult('join_', resultSelector),
      );

  /// LEFT OUTER JOIN: each outer element is paired with a list of
  /// matching inner elements (the list is empty if no match).
  ///
  /// Parameters:
  ///
  /// * [inner] — the right-hand side of the join.
  /// * [outerKeySelector] — single-parameter [LambdaExpr].
  /// * [innerKeySelector] — single-parameter [LambdaExpr].
  /// * [resultSelector] — three-parameter [LambdaExpr]:
  /// `(o, inners, k) => r` where `inners` is a `List<TInner>`.
  IQueryable<TResult> groupJoin_<TInner, TKey, TResult>({
    required IQueryable<TInner> inner,
    required Expr outerKeySelector,
    required Expr innerKeySelector,
    required Expr resultSelector,
  }) =>
      _GroupJoinEnumerableQuery<TOuter, TInner, TKey, TResult>(
        this,
        inner,
        _requireKey('groupJoin_', outerKeySelector),
        _requireKey('groupJoin_', innerKeySelector),
        _requireResult('groupJoin_', resultSelector),
      );
}

// ─── join_ ───────────────────────────────────────────────────────────

class _JoinEnumerableQuery<TOuter, TInner, TKey, TResult>
    extends IQueryable<TResult> {
  final IQueryable<TOuter> _outer;
  final IQueryable<TInner> _inner;
  final LambdaExpr _outerKey;
  final LambdaExpr _innerKey;
  final LambdaExpr _result;

  _JoinEnumerableQuery(
      this._outer, this._inner, this._outerKey, this._innerKey, this._result);

  @override
  IQueryProvider get provider => _outer.provider;

  @override
  Expr? get expression => null;

  @override
  Iterator<TResult> get iterator {
    // Build the inner index once.
    final index = <Object, List<TInner>>{};
    final innerParam = _innerKey.params.first.name;
    for (final i in _inner) {
      final k = _innerKey.body.eval({innerParam: i});
      index.putIfAbsent(k as Object, () => []).add(i);
    }
    // Now stream the outer.
    final outerParam = _outerKey.params.first.name;
    final resultParams = _result.params;
    final outParam = resultParams[0].name;
    final inParam = resultParams[1].name;
    final resultBody = _result.body;
    final out = <TResult>[];
    for (final o in _outer) {
      final ok = _outerKey.body.eval({outerParam: o});
      final matches = index[ok as Object] ?? const [];
      for (final i in matches) {
        out.add(resultBody.eval({outParam: o, inParam: i}) as TResult);
      }
    }
    return out.iterator;
  }
}

// ─── groupJoin_ ──────────────────────────────────────────────────────

class _GroupJoinEnumerableQuery<TOuter, TInner, TKey, TResult>
    extends IQueryable<TResult> {
  final IQueryable<TOuter> _outer;
  final IQueryable<TInner> _inner;
  final LambdaExpr _outerKey;
  final LambdaExpr _innerKey;
  final LambdaExpr _result;

  _GroupJoinEnumerableQuery(
      this._outer, this._inner, this._outerKey, this._innerKey, this._result);

  @override
  IQueryProvider get provider => _outer.provider;

  @override
  Expr? get expression => null;

  @override
  Iterator<TResult> get iterator {
    final index = <Object, List<TInner>>{};
    final innerParam = _innerKey.params.first.name;
    for (final i in _inner) {
      final k = _innerKey.body.eval({innerParam: i});
      index.putIfAbsent(k as Object, () => []).add(i);
    }
    final outerParam = _outerKey.params.first.name;
    final resultParams = _result.params;
    final outParam = resultParams[0].name;
    final insParam = resultParams[1].name;
    final keyParam = resultParams[2].name;
    final resultBody = _result.body;
    final out = <TResult>[];
    for (final o in _outer) {
      final ok = _outerKey.body.eval({outerParam: o});
      final matches = index[ok as Object] ?? <TInner>[];
      out.add(
        resultBody.eval({
          outParam: o,
          insParam: matches,
          keyParam: ok,
        }) as TResult,
      );
    }
    return out.iterator;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────

LambdaExpr _requireKey(String opName, Expr selector) {
  if (selector is! LambdaExpr || selector.params.length != 1) {
    throw ArgumentError(
      '$opName key selectors must be single-parameter LambdaExpr, got ${selector.runtimeType}',
    );
  }
  return selector;
}

LambdaExpr _requireResult(String opName, Expr selector) {
  if (selector is! LambdaExpr) {
    throw ArgumentError(
      '$opName resultSelector must be a LambdaExpr, got ${selector.runtimeType}',
    );
  }
  final lambda = selector;
  // join_ takes 2 params (outer, inner).
  // groupJoin_ takes 3 params (outer, inners, key).
  // We don't know which one we're in here, so we accept either.
  if (lambda.params.length != 2 && lambda.params.length != 3) {
    throw ArgumentError(
      '$opName resultSelector must take 2 (outer, inner) or 3 '
      '(outer, inners, key) parameters, got ${lambda.params.length}',
    );
  }
  return lambda;
}
