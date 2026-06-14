/// Conversion LINQ operators: `toList_`, `toSet_`, `toMap_`,
/// `asEnumerable_`, `cast_`, `toDictionary_`, `toLookup_`.
///
/// These are terminal operators that materialize the source into
/// a concrete Dart collection. Most of them are thin wrappers over
/// the corresponding `Iterable` extension methods.
library;

import '../enumerable_query.dart';
import '../expr.dart';
import '../i_queryable.dart';

extension ConversionsOp<T> on IQueryable<T> {
  /// Materializes the queryable into a `List<T>`.
  ///
  /// Equivalent to `this.toList` but kept for naming parity with
  /// C# LINQ.
  List<T> toList_() => toList();

  /// Materializes the queryable into a `Set<T>`.
  Set<T> toSet_() => toSet();

  /// Materializes the queryable into a `Map<TKey, T>` using the
  /// [keySelector] to extract the key for each element.
  ///
  /// Throws [StateError] if two elements produce the same key.
  ///
  /// Example:
  ///
  /// ```dart
  /// final byId = users.asQueryable.toMap_`<int>`(
  /// keySelector: Expr.lambda(
  /// [Expr.param('u')],
  /// Expr.member(Expr.param('u'), 'id'),
  ///),
  ///);
  /// ```
  Map<TKey, T> toMap_<TKey>({required Expr keySelector}) {
    final lambda = _requireKey('toMap_', keySelector);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    final out = <TKey, T>{};
    for (final e in this) {
      final k = body.eval({paramName: e}) as TKey;
      if (out.containsKey(k)) {
        throw StateError('toMap_: duplicate key $k');
      }
      out[k] = e;
    }
    return out;
  }

  /// Returns the queryable as a plain `Iterable<T>`. Useful at the
  /// boundary between LINQ code and `dart:core` collection APIs.
  Iterable<T> asEnumerable_() => this;

  /// Casts each element of the source to [TResult]. Returns an
  /// `IQueryable<TResult>` whose elements are the cast results.
  ///
  /// Throws [TypeError] on a mismatch.
  IQueryable<TResult> cast_<TResult>() =>
      EnumerableQuery<TResult>(cast<TResult>());
}

extension ConversionMapOps<TKey, T> on IQueryable<T> {
  /// (Intentionally not defined on `IQueryable<T>`. The
  /// `toDictionary_` operator lives on a queryable of `MapEntry`
  /// or with a key/value selector pair, mirroring the C# signature.)
}

// ─── Internal helpers ────────────────────────────────────────────────

LambdaExpr _requireKey(String opName, Expr keySelector) {
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
