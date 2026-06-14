/// `ILookup<TKey, TElement>` — a multi-valued dictionary.
///
///: ported to d_rocket (previously lived in
/// the in-memory LINQ operators only). A `Lookup` is
/// like a `Map<TKey, List<TElement>>` but with extra
/// semantics:
///
/// - Keys can map to zero or more values.
/// - `operator ` returns an empty iterable for
/// missing keys (never null).
/// - `containsKey` distinguishes "no value" from
/// "value is empty".
///
/// Usage:
///
/// ```dart
/// final byName = db.set`<User>`
/// .where_(...)
/// .toLookup_`<String>`(keySelector: Expr.lambda(
/// [Expr.param('u')],
/// Expr.member(Expr.param('u'), 'name'),
///));
/// print(byName[''].length);
/// ```
library;

import '../expr.dart';
import 'group_by.dart';

///: the public interface for a lookup.
/// The `toLookup_` operator returns a `_Lookup` (the
/// concrete impl in `lib/src/sqlite/queryable.dart`).
abstract class ILookup<TKey, TElement>
    extends Iterable<IGrouping<TKey, TElement>> {
  ///: `true` if the lookup has at least
  /// one element under [key].
  bool containsKey(TKey key);

  ///: returns the values for [key], or
  /// an empty iterable if [key] is absent.
  Iterable<TElement> operator [](TKey key);

  ///: the number of distinct keys in
  /// the lookup.
  @override
  int get length;

  ///: the distinct keys in the lookup
  /// (order is insertion order).
  Iterable<TKey> get keys;
}

/// (in-memory helper): builds a [ILookup]
/// from a source `Iterable<T>` and a key extractor.
/// Reused by both the SQL-backed `Queryable.toLookup_`
/// and the in-memory `IQueryable.toLookup_` extensions.
ILookup<TKey, T> buildLookup<T, TKey>(
  Iterable<T> source,
  LambdaExpr keySelector,
) {
  final paramName = keySelector.params.first.name;
  final body = keySelector.body;
  final Map<TKey, List<T>> grouped = <TKey, List<T>>{};
  for (final T row in source) {
    final TKey key = body.eval(<String, Object?>{paramName: row}) as TKey;
    grouped.putIfAbsent(key, () => <T>[]).add(row);
  }
  return _LookupImpl<TKey, T>._(grouped);
}

class _LookupImpl<TKey, T> extends ILookup<TKey, T> {
  _LookupImpl._(this._map);
  final Map<TKey, List<T>> _map;

  @override
  bool containsKey(TKey key) => _map.containsKey(key);

  @override
  Iterable<T> operator [](TKey key) => _map[key] ?? const <Never>[];

  @override
  int get length => _map.length;

  @override
  Iterable<TKey> get keys => _map.keys;

  @override
  Iterator<IGrouping<TKey, T>> get iterator => _map.entries
      .map(
          (MapEntry<TKey, List<T>> e) => _GroupingImpl<TKey, T>(e.key, e.value))
      .iterator;
}

class _GroupingImpl<TKey, T> extends IGrouping<TKey, T> {
  _GroupingImpl(this._key, this._elements);
  final TKey _key;
  final List<T> _elements;

  @override
  TKey get key => _key;

  @override
  Iterator<T> get iterator => _elements.iterator;
}

/// (in-memory extension): builds a
/// `ILookup<TKey, T>` from any `IQueryable<T>` (this
/// is the in-memory counterpart of
/// `Queryable.toLookup_`). Materialises the source
/// in memory.
extension InMemoryLookupOp<T> on Iterable<T> {
  ///: groups the source by [keySelector].
  /// The result is iterable: iterate to get
  /// `IGrouping<TKey, T>` entries (one per key).
  ///
  /// For random access by key (`.containsKey`, ``),
  /// use `Queryable.toLookup_` on a SQL-backed
  /// queryable.
  ILookup<TKey, T> toLookup_<TKey>({required Expr keySelector}) {
    final LambdaExpr lambda = _requireLambda('toLookup_', keySelector);
    return buildLookup<T, TKey>(this, lambda);
  }
}

LambdaExpr _requireLambda(String op, Expr e) {
  if (e is LambdaExpr) return e;
  throw ArgumentError(
    '$op: argument must be a LambdaExpr '
    '(use Expr.lambda([Expr.param(...), ...], body)).',
  );
}
