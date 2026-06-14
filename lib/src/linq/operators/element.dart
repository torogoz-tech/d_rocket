/// Element LINQ operators: `first_`, `firstOrDefault_`, `single_`,
/// `singleOrDefault_`, `elementAt_`, `elementAtOrDefault_`.
///
/// All of these are terminal operators (they return a single
/// element, or throw). They short-circuit iteration as soon as the
/// result is determined.
///
/// ## Variants
///
/// * `first_` / `first_(where: predicate)` — first element.
/// * `firstOrDefault_` / `firstOrDefault_(where: predicate)` —
/// first element or `null` if the source is empty.
/// * `single_` / `single_(where: predicate)` — exactly one element.
/// Throws if there are zero or more than one.
/// * `singleOrDefault_` / `singleOrDefault_(where: predicate)` —
/// zero or one element, otherwise `null` (or throws if more than
/// one).
/// * `elementAt_(index)` — element at [index]. Throws on out-of-range.
/// * `elementAtOrDefault_(index)` — element at [index] or `null`.
///
/// `first_` and `single_` (and the `*OrDefault` variants) use a
/// named `where:` parameter to disambiguate the no-arg and predicate
/// forms, since Dart does not allow method overloading.
library;

import '../expr.dart';
import '../i_queryable.dart';

extension ElementOp<T> on IQueryable<T> {
  /// Returns the first element of the source, or the first element
  /// matching the optional [where] predicate.
  ///
  /// Throws [StateError] if no element matches.
  T first_({Expr? where}) => _firstOrSingle(
        this,
        where: where,
        opName: 'first_',
        requireExactlyOne: false,
        orDefault: false,
      );

  /// Returns the first element of the source, or `null` if the source
  /// is empty (or no element matches the optional [where] predicate).
  T? firstOrDefault_({Expr? where}) => _firstOrSingle<T?>(
        this,
        where: where,
        opName: 'firstOrDefault_',
        requireExactlyOne: false,
        orDefault: true,
      );

  /// Returns the only element of the source (or the only one matching
  /// the optional [where] predicate).
  ///
  /// Throws [StateError] if the source has zero or more than one
  /// matching element.
  T single_({Expr? where}) => _firstOrSingle(
        this,
        where: where,
        opName: 'single_',
        requireExactlyOne: true,
        orDefault: false,
      );

  /// Returns the only element of the source, or `null` if there are
  /// zero matching elements. Throws [StateError] if there is more
  /// than one matching element.
  T? singleOrDefault_({Expr? where}) => _firstOrSingle<T?>(
        this,
        where: where,
        opName: 'singleOrDefault_',
        requireExactlyOne: true,
        orDefault: true,
      );

  /// Returns the element at [index]. Throws [RangeError] on
  /// out-of-range indices.
  T elementAt_(int index) {
    if (index < 0) {
      throw RangeError.index(index, this, 'elementAt_');
    }
    var i = 0;
    for (final e in this) {
      if (i == index) return e;
      i++;
    }
    throw RangeError.index(index, this, 'elementAt_');
  }

  /// Returns the element at [index] or `null` if the index is
  /// out-of-range.
  T? elementAtOrDefault_(int index) {
    if (index < 0) return null;
    var i = 0;
    for (final e in this) {
      if (i == index) return e;
      i++;
    }
    return null;
  }
}

// ─── Internal helper ─────────────────────────────────────────────────

T? _firstOrSingle<T>(
  IQueryable source, {
  Expr? where,
  required String opName,
  required bool requireExactlyOne,
  required bool orDefault,
}) {
  String? paramName;
  Expr? body;
  if (where != null) {
    if (where is! LambdaExpr || where.params.length != 1) {
      throw ArgumentError(
        '$opName where must be a single-parameter LambdaExpr',
      );
    }
    paramName = where.params.first.name;
    body = where.body;
  }
  Object? result;
  var found = false;
  for (final e in source) {
    if (body == null || body.eval({paramName!: e}) == true) {
      if (requireExactlyOne && found) {
        throw StateError(
          '$opName found more than one matching element',
        );
      }
      result = e;
      found = true;
      if (!requireExactlyOne) break; // first_ short-circuits.
    }
  }
  if (!found) {
    if (orDefault) return null;
    throw StateError('$opName found no matching element');
  }
  return result as T;
}
