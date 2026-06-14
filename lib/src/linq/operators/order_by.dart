/// The `orderBy_` family of LINQ operators (sorting).
///
/// * `orderBy_(keySelector)` — ascending sort by the selector's value.
/// * `orderByDescending_(keySelector)` — descending sort.
/// * `thenBy_(keySelector)` — secondary ascending sort, must follow
/// an `orderBy_` or `thenBy_`.
/// * `thenByDescending_(keySelector)` — secondary descending sort.
///
/// The implementation materializes the source (no streaming sort in
///). In (SQLite) the whole chain is translated to a
/// single SQL `ORDER BY a ASC, b DESC`.
library;

import '../expr.dart';
import '../i_query_provider.dart';
import '../i_queryable.dart';

/// The `orderBy_` LINQ operator.
extension OrderByOp<T> on IQueryable<T> {
  /// Sorts the elements in ascending order of the values produced by
  /// [keySelector].
  ///
  /// The [keySelector] must be a single-parameter [LambdaExpr] that
  /// returns a comparable value.
  ///
  /// Example:
  ///
  /// ```dart
  /// final byAge = users.asQueryable.orderBy_(
  /// Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'age'),
  ///),
  ///).toList;
  /// ```
  IQueryable<T> orderBy_(Expr keySelector) {
    final key = _requireKeySelector('orderBy_', keySelector);
    return _OrderedEnumerableQuery<T>(this, [
      _OrderByKey(key, ascending: true),
    ]);
  }

  /// Sorts the elements in descending order of the values produced by
  /// [keySelector].
  IQueryable<T> orderByDescending_(Expr keySelector) {
    final key = _requireKeySelector('orderByDescending_', keySelector);
    return _OrderedEnumerableQuery<T>(this, [
      _OrderByKey(key, ascending: false),
    ]);
  }
}

/// The `thenBy_` / `thenByDescending_` operators, available only on
/// queryables that have already been ordered.
extension ThenByOp<T> on IQueryable<T> {
  /// Adds a secondary ascending sort to the ordering.
  IQueryable<T> thenBy_(Expr keySelector) {
    final key = _requireKeySelector('thenBy_', keySelector);
    return _appendOrder(this, _OrderByKey(key, ascending: true));
  }

  /// Adds a secondary descending sort to the ordering.
  IQueryable<T> thenByDescending_(Expr keySelector) {
    final key = _requireKeySelector('thenByDescending_', keySelector);
    return _appendOrder(this, _OrderByKey(key, ascending: false));
  }
}

// ─── Internal helpers ────────────────────────────────────────────────

class _OrderByKey {
  final LambdaExpr selector;
  final bool ascending;
  const _OrderByKey(this.selector, {required this.ascending});
}

LambdaExpr _requireKeySelector(String opName, Expr keySelector) {
  if (keySelector is! LambdaExpr) {
    throw ArgumentError(
      '$opName keySelector must be a LambdaExpr, got ${keySelector.runtimeType}',
    );
  }
  final lambda = keySelector;
  if (lambda.params.length != 1) {
    throw ArgumentError(
      '$opName keySelector must take exactly 1 parameter, got ${lambda.params.length}',
    );
  }
  return lambda;
}

IQueryable<T> _appendOrder<T>(IQueryable<T> q, _OrderByKey key) {
  if (q is _OrderedEnumerableQuery<T>) {
    return _OrderedEnumerableQuery<T>(q._source, [...q._keys, key]);
  }
  // C# throws InvalidOperationException for thenBy without preceding
  // orderBy. We do the same: it's a programming error.
  throw StateError(
    'thenBy_/thenByDescending_ must follow an orderBy_, orderByDescending_, '
    'or another thenBy_. The current queryable is not ordered.',
  );
}

class _OrderedEnumerableQuery<T> extends IQueryable<T> {
  final IQueryable<T> _source;
  final List<_OrderByKey> _keys;

  _OrderedEnumerableQuery(this._source, this._keys);

  @override
  IQueryProvider get provider => _source.provider;

  @override
  Expr? get expression => null;

  @override
  Iterator<T> get iterator {
    final materialized = _source.toList();
    final keys = _keys;
    materialized.sort((a, b) {
      for (final k in keys) {
        final ka = k.selector.body.eval({k.selector.params.first.name: a});
        final kb = k.selector.body.eval({k.selector.params.first.name: b});
        final cmp = _compare(ka, kb);
        if (cmp != 0) return k.ascending ? cmp : -cmp;
      }
      return 0;
    });
    return materialized.iterator;
  }
}

int _compare(Object? a, Object? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a is num && b is num) {
    return a.compareTo(b);
  }
  if (a is String && b is String) {
    return a.compareTo(b);
  }
  if (a is DateTime && b is DateTime) {
    return a.compareTo(b);
  }
  if (a is Comparable && b is Comparable) {
    // Best effort. The above specific cases handle the common types.
    // For anything else, fall back to a lexicographic toString compare.
    if (a.runtimeType == b.runtimeType) {
      return (a as dynamic).compareTo(b) as int;
    }
  }
  return a.toString().compareTo(b.toString());
}
