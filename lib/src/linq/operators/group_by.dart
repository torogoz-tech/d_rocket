/// The `groupBy_` LINQ operator (group by a key selector).
///
/// Returns an `IQueryable<IGrouping<TKey, T>>` where each element is
/// a group of source items that share the same key.
///
/// In (SQLite) `groupBy_` translates to `GROUP BY` (with an
/// optional `HAVING` and `SELECT` for the element selector).
library;

import '../enumerable_query.dart';
import '../expr.dart';
import '../i_queryable.dart';

/// A group of elements sharing a key.
///
/// Implements [RecordLike] so that LINQ expressions can read the
/// `key` and `length` (and any other user-defined property) via the
/// standard [MemberAccessExpr] / [Expr.readField] machinery.
abstract class IGrouping<TKey, T> extends Iterable<T> implements RecordLike {
  TKey get key;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'key' => key,
        'length' => length,
        _ => null,
      };
}

extension GroupByOp<T> on IQueryable<T> {
  /// Groups elements by the value produced by [keySelector].
  ///
  /// The [keySelector] must be a single-parameter [LambdaExpr].
  ///
  /// Example:
  ///
  /// ```dart
  /// final byAge = users.asQueryable.groupBy_`<int>`(
  /// keySelector: Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'age'),
  ///),
  ///);
  /// for (final group in byAge) {
  /// print('Age ${group.key}: ${group.length} user(s)');
  /// }
  /// ```
  IQueryable<IGrouping<TKey, T>> groupBy_<TKey>({
    required Expr keySelector,
  }) {
    final lambda = _requireKey('groupBy_', keySelector);
    return EnumerableQuery<IGrouping<TKey, T>>(_groupBy(this, lambda));
  }
}

// ─── Internal helpers ────────────────────────────────────────────────

LambdaExpr _requireKey(String opName, Expr keySelector) {
  if (keySelector is! LambdaExpr || keySelector.params.length != 1) {
    throw ArgumentError(
      '$opName keySelector must be a single-parameter LambdaExpr',
    );
  }
  return keySelector;
}

Iterable<IGrouping<TKey, T>> _groupBy<T, TKey>(
  Iterable<T> source,
  LambdaExpr keySelector,
) sync* {
  final paramName = keySelector.params.first.name;
  final body = keySelector.body;
  final index = <Object, List<T>>{};
  final keyOrder = <Object>[];
  for (final e in source) {
    final k = body.eval({paramName: e}) as Object;
    final list = index[k];
    if (list == null) {
      index[k] = [e];
      keyOrder.add(k);
    } else {
      list.add(e);
    }
  }
  for (final k in keyOrder) {
    yield _Grouping<TKey, T>(k as TKey, index[k]!);
  }
}

class _Grouping<TKey, T> extends IGrouping<TKey, T> {
  _Grouping(this.key, this._items);
  @override
  final TKey key;
  final List<T> _items;

  @override
  Iterator<T> get iterator => _items.iterator;
}
