/// Aggregate LINQ operators: `count_`, `longCount_`, `sum_`,
/// `average_`, `min_`, `max_`, `aggregate_`.
///
/// All of these are terminal operators (they return a scalar).
/// In we implement them on `IQueryable<T>` directly using
/// the in-memory iteration. In (SQLite) they will be
/// translated to `SELECT COUNT(*)`, `SELECT SUM(x)`, etc.
///
/// ## Two flavors
///
/// `count_` and `longCount_` each have two forms (no args, or with
/// a `where:` predicate). Because Dart does not allow overloading,
/// they are exposed as a single method with an optional named
/// parameter:
///
/// * `count_` — counts elements.
/// * `count_(where: predicate)` — counts elements matching a predicate.
///
/// `sum_`/`average_`/`min_`/`max_` all take a single-parameter
/// `LambdaExpr` selector that projects each element to a comparable
/// value.
library;

import '../expr.dart';
import '../i_queryable.dart';

extension AggregatesOp<T> on IQueryable<T> {
  /// Returns the number of elements in the source. If [where] is
  /// provided, only elements matching the predicate are counted.
  int count_({Expr? where}) {
    if (where == null) {
      var n = 0;
      for (final _ in this) {
        n++;
      }
      return n;
    }
    final lambda = _requireSelector('count_', where);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    var n = 0;
    for (final e in this) {
      if (body.eval({paramName: e}) == true) n++;
    }
    return n;
  }

  /// Same as [count_] but kept for API parity with C# LINQ. On the
  /// Dart VM `int` is 64-bit on native, so there is no overflow risk
  /// in practice; this method exists for naming consistency.
  int longCount_({Expr? where}) => count_(where: where);

  /// Returns the sum of the values produced by the [selector]
  /// LambdaExpr. The values must be `num` (int or double).
  num sum_(Expr selector) {
    final lambda = _requireSelector('sum_', selector);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    num total = 0;
    var sawAny = false;
    for (final e in this) {
      final v = body.eval({paramName: e});
      if (v is num) {
        total += v;
        sawAny = true;
      } else if (v != null) {
        throw StateError('sum_ selector returned non-numeric: $v');
      }
    }
    if (!sawAny) {
      // C# throws InvalidOperationException for an empty source.
      // In we return 0 for ergonomic Dart idioms;
      // can revisit to match C# strictly.
      return 0;
    }
    return total;
  }

  /// Returns the arithmetic mean of the values produced by the
  /// [selector] LambdaExpr. Throws [StateError] on an empty source.
  double average_(Expr selector) {
    final lambda = _requireSelector('average_', selector);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    num total = 0;
    var count = 0;
    for (final e in this) {
      final v = body.eval({paramName: e});
      if (v is num) {
        total += v;
        count++;
      } else if (v != null) {
        throw StateError('average_ selector returned non-numeric: $v');
      }
    }
    if (count == 0) {
      throw StateError('average_ called on empty source');
    }
    return total / count;
  }

  /// Returns the smallest value produced by the [selector]
  /// LambdaExpr. Throws [StateError] on an empty source.
  Object? min_(Expr selector) {
    final lambda = _requireSelector('min_', selector);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    Object? best;
    var hasBest = false;
    for (final e in this) {
      final v = body.eval({paramName: e});
      if (!hasBest) {
        best = v;
        hasBest = true;
        continue;
      }
      final cmp = _compareForOrder(v, best);
      if (cmp != null && cmp < 0) {
        best = v;
      }
    }
    if (!hasBest) {
      throw StateError('min_ called on empty source');
    }
    return best;
  }

  /// Returns the largest value produced by the [selector]
  /// LambdaExpr. Throws [StateError] on an empty source.
  Object? max_(Expr selector) {
    final lambda = _requireSelector('max_', selector);
    final paramName = lambda.params.first.name;
    final body = lambda.body;
    Object? best;
    var hasBest = false;
    for (final e in this) {
      final v = body.eval({paramName: e});
      if (!hasBest) {
        best = v;
        hasBest = true;
        continue;
      }
      final cmp = _compareForOrder(v, best);
      if (cmp != null && cmp > 0) {
        best = v;
      }
    }
    if (!hasBest) {
      throw StateError('max_ called on empty source');
    }
    return best;
  }

  /// Applies an accumulator function over the source.
  ///
  /// [seed] is the initial accumulator value. [func] is a two-parameter
  /// LambdaExpr: `(acc, x) => nextAcc`. The result of the last
  /// invocation is returned.
  ///
  /// Example:
  ///
  /// ```dart
  /// final joined = users
  /// .asQueryable
  /// .aggregate_`<String>`(
  /// seed: '',
  /// func: Expr.lambda(
  /// [Expr.param('acc'), Expr.param('u')],
  /// Expr.binary(
  /// '+',
  /// Expr.param('acc'),
  /// Expr.member(Expr.param('u'), 'name'),
  ///),
  ///),
  ///);
  /// // → 'AliceBobCarol'
  /// ```
  TResult aggregate_<TResult>({
    required TResult seed,
    required Expr func,
  }) {
    if (func is! LambdaExpr) {
      throw ArgumentError(
        'aggregate_ func must be a LambdaExpr, got ${func.runtimeType}',
      );
    }
    final lambda = func;
    if (lambda.params.length != 2) {
      throw ArgumentError(
        'aggregate_ func must take exactly 2 parameters (acc, x), got '
        '${lambda.params.length}',
      );
    }
    final accName = lambda.params[0].name;
    final xName = lambda.params[1].name;
    final body = lambda.body;
    var acc = seed;
    for (final e in this) {
      acc = body.eval({accName: acc, xName: e}) as TResult;
    }
    return acc;
  }
}

// ─── Internal helpers ────────────────────────────────────────────────

LambdaExpr _requireSelector(String opName, Expr selector) {
  if (selector is! LambdaExpr) {
    throw ArgumentError(
      '$opName selector must be a LambdaExpr, got ${selector.runtimeType}',
    );
  }
  final lambda = selector;
  if (lambda.params.length != 1) {
    throw ArgumentError(
      '$opName selector must take exactly 1 parameter, got ${lambda.params.length}',
    );
  }
  return lambda;
}

int? _compareForOrder(Object? a, Object? b) {
  if (a is num && b is num) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  if (a is DateTime && b is DateTime) return a.compareTo(b);
  // Incommensurable (e.g. a is int and b is String). We can't
  // compare, so we leave the current best in place. This matches
  // C# LINQ's behavior: a heterogeneous queryable returns the
  // first-encountered value.
  return null;
}
