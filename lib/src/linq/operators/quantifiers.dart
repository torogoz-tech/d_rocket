/// Quantifier LINQ operators: `any_`, `all_`, `contains_`.
///
/// These are terminal operators (they return `bool`, not
/// `IQueryable`). They iterate the source until the result is known
/// (short-circuit semantics).
///
/// * `any_` — is there at least one element?
/// * `any_(where: predicate)` — is there an element matching [predicate]?
/// * `all_(predicate)` — do all elements match [predicate]? Vacuously
/// true for an empty source.
/// * `contains_(value)` — is [value] in the source?
///
/// Note: `any_` uses a named `where:` parameter to disambiguate
/// the no-arg and predicate forms, since Dart does not allow method
/// overloading.
library;

import '../expr.dart';
import '../i_queryable.dart';

extension QuantifiersOp<T> on IQueryable<T> {
  /// Returns `true` if the source has at least one element, or if at
  /// least one element satisfies the optional [where] predicate.
  ///
  /// Short-circuits at the first match.
  ///
  /// Example:
  ///
  /// ```dart
  /// if (users.asQueryable.any_) { … }
  /// if (users.asQueryable.any_(where: isAdult)) { … }
  /// ```
  bool any_({Expr? where}) {
    if (where == null) {
      return iterator.moveNext();
    }
    final lambda = _requirePredicate('any_', where);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    for (final e in this) {
      if (body.eval({paramName: e}) == true) return true;
    }
    return false;
  }

  /// Returns `true` if all elements satisfy [predicate]. Vacuously
  /// true for an empty source.
  ///
  /// Short-circuits at the first non-match.
  bool all_(Expr predicate) {
    final lambda = _requirePredicate('all_', predicate);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    for (final e in this) {
      if (body.eval({paramName: e}) != true) return false;
    }
    return true;
  }

  /// Returns `true` if [value] is an element of the source, compared
  /// with `==` (and `hashCode`).
  ///
  /// Example:
  ///
  /// ```dart
  /// if (ages.asQueryable.contains_(42)) { … }
  /// ```
  bool contains_(T value) {
    for (final e in this) {
      if (e == value) return true;
    }
    return false;
  }
}

LambdaExpr _requirePredicate(String opName, Expr predicate) {
  if (predicate is! LambdaExpr) {
    throw ArgumentError(
      '$opName predicate must be a LambdaExpr, got ${predicate.runtimeType}',
    );
  }
  final lambda = predicate;
  if (lambda.params.length != 1) {
    throw ArgumentError(
      '$opName predicate must take exactly 1 parameter, got ${lambda.params.length}',
    );
  }
  return lambda;
}
