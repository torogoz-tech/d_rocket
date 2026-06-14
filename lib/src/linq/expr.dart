/// Expression-tree DSL for the LINQ layer of `d_rocket`.
///
/// This is the runtime path of the LINQ implementation. The
/// user builds an [Expr] tree that represents a query predicate,
/// selector, or any composable computation. The tree is then consumed
/// by an [IQueryProvider] (in-memory in, SQLite in, etc.).
///
/// ## Two ways to build a tree
///
/// 1. Manually (verbose but always available, no codegen):
///
/// ```dart
/// final adults$expr = Expr.lambda(
/// [Expr.param('u')],
/// Expr.binary(
/// '>',
/// Expr.member(Expr.param('u'), 'age'),
/// Expr.const_(18),
///),
///);
/// ```
///
/// 2. Via codegen (, `d_rocket_builder`): the user writes a
/// normal Dart lambda and the codegen lifts it to this DSL:
///
/// ```dart
/// // User code:
/// final adults = ctx.users.where((u) => u.age > 18).toList;
///
/// // Generated to *.rocket.g.dart:
/// final adults$expr = Expr.lambda(
/// [Expr.param('u')],
/// Expr.binary('>',
/// Expr.member(Expr.param('u'), 'age'),
/// Expr.const_(18)),
///);
/// final adults = ctx.users.where(adults$expr).toList;
/// ```
///
/// ## Anatomy of a tree
///
/// A [LambdaExpr] wraps a body expression with parameter declarations.
/// The body is one of: a [ConstExpr], a [ParamExpr], a [BinaryExpr],
/// a [UnaryExpr], a [MemberAccessExpr], a [MethodCallExpr], a
/// [NullExpr], or a [ListExpr].
///
/// [Expr.eval] evaluates a tree against a context map; the in-memory
/// provider uses this. [Expr.accept] runs a visitor — used by the
/// SQLite translator in .
library;

// ─── Sealed root ─────────────────────────────────────────────────────

sealed class Expr {
  const Expr();

  /// External visitor for providers (SQL translator, codegen emitter, …).
  R accept<R>(ExprVisitor<R> visitor);

  /// In-memory evaluation against a context.
  Object? eval(Map<String, Object?> ctx);

  @override
  String toString();

  // ─── Static factory methods ──────────────────────────────────────
  //
  // These are the public API for building trees. They live on the
  // sealed root so users can write `Expr.param('x')` instead of having
  // to import a separate factory class.

  /// The constant `null`.
  static const Expr null_ = NullExpr();

  /// A constant value (int, double, String, bool, null, …).
  static Expr const_(Object? value) => ConstExpr(value);

  /// A reference to a parameter named [name] (e.g. `'u'` in `(u) => …`).
  static Expr param(String name) => ParamExpr(name);

  /// A lambda: a list of parameters and a body expression.
  static Expr lambda(List<Expr> params, Expr body) =>
      LambdaExpr(params.cast<ParamExpr>(), body);

  /// A binary operation. Supports: `+ - * / % == != < <= > >= && ||`.
  static Expr binary(String op, Expr left, Expr right) =>
      BinaryExpr(op, left, right);

  /// A unary operation. Supports: `! -`.
  static Expr unary(String op, Expr operand) => UnaryExpr(op, operand);

  /// Member access: `target.name`.
  static Expr member(Expr target, String name) =>
      MemberAccessExpr(target, name);

  /// Method call: `target.method(arg0, arg1, …)`.
  static Expr call(Expr target, String method, List<Expr> args) =>
      MethodCallExpr(target, method, args);

  /// A list literal: `[a, b, c]`.
  static Expr list(List<Expr> items) => ListExpr(items);

  /// .e: a map literal
  /// `{'a': 1, 'b': 2}`. The [entries] are evaluated
  /// left-to-right; the result is a `Map<Object, Object>`
  /// (keys can be any evaluated value).
  static Expr map(List<MapEntry<Expr, Expr>> entries) =>
      MapLiteralExpr(entries);

  /// .e: a ternary expression
  /// `cond ? thenBranch: elseBranch`. Evaluates
  /// [cond]; if truthy returns [thenBranch].eval,
  /// else [elseBranch].eval.
  static Expr ternary({
    required Expr cond,
    required Expr thenBranch,
    required Expr elseBranch,
  }) =>
      TernaryExpr(cond, thenBranch, elseBranch);

  /// .e: a null-coalesce `a ?? b`.
  /// Returns `a.eval(ctx)` if non-null, else `b.eval(ctx)`.
  /// Translates to SQL `COALESCE(a, b)`.
  static Expr coalesce(Expr left, Expr right) => CoalesceExpr(left, right);

  /// .e: a null-safe member access
  /// `a?.b`. Returns `null` if `a` evaluates to `null`,
  /// else performs a regular member access. Translates
  /// to SQL via `CASE WHEN a IS NULL THEN NULL ELSE …`.
  static Expr nullSafe(Expr target, String member) =>
      NullSafeAccessExpr(target, member);

  /// (new): an aggregate call. Translates
  /// to `SUM(selector)`, `COUNT(selector)`, `AVG(selector)`,
  /// `MIN(selector)`, `MAX(selector)` in SQL. The
  /// in-memory provider evaluates the selector over each
  /// element and folds with the matching Dart operator.
  static Expr aggregate(
    String function, {
    required Expr selector,
    bool distinct = false,
  }) =>
      AggregateExpr(distinct: distinct, function, selector);

  /// (new): a `GROUP BY` expression. The
  /// [keySelector] partitions the source into
  /// `IGrouping<K, T>`; the [elementSelector] (optional)
  /// projects each element; the [havingPredicate]
  /// (optional) filters groups after aggregation.
  /// Translates to a single `SELECT ... FROM ... GROUP BY
  /// ... [HAVING ...]` statement.
  static Expr groupBy({
    required Expr keySelector,
    Expr? elementSelector,
    Expr? havingPredicate,
  }) =>
      GroupByExpr(
        keySelector: keySelector,
        elementSelector: elementSelector,
        havingPredicate: havingPredicate,
      );

  /// (new): a post-aggregation `HAVING`
  /// predicate. Distinct from a regular [binary] (a
  /// HAVING predicate is allowed to reference aggregate
  /// functions like `SUM(x) > 100`).
  static Expr having(Expr predicate) => HavingExpr(predicate);

  /// (new): a relational `JOIN` between
  /// [outer] and [inner] queryables. The [outerKey] and
  /// [innerKey] selectors extract the join key from each
  /// side; the [resultSelector] projects the pair into
  /// the final row shape. Translates to
  /// `... LEFT|RIGHT|INNER JOIN ... ON outerKey = innerKey`.
  static Expr join({
    required Expr outer,
    required Expr inner,
    required Expr outerKey,
    required Expr innerKey,
    required Expr resultSelector,
    String joinType = 'INNER',
  }) =>
      JoinExpr(
        outer: outer,
        inner: inner,
        outerKey: outerKey,
        innerKey: innerKey,
        resultSelector: resultSelector,
        joinType: joinType,
      );
}

// ─── Visitor ─────────────────────────────────────────────────────────

abstract class ExprVisitor<R> {
  R visitConst(ConstExpr e);
  R visitParam(ParamExpr e);
  R visitLambda(LambdaExpr e);
  R visitBinary(BinaryExpr e);
  R visitUnary(UnaryExpr e);
  R visitMemberAccess(MemberAccessExpr e);
  R visitMethodCall(MethodCallExpr e);
  R visitNull(NullExpr e);
  R visitList(ListExpr e);
  R visitAggregate(AggregateExpr e);
  R visitGroupBy(GroupByExpr e);
  R visitHaving(HavingExpr e);
  R visitJoin(JoinExpr e);

  /// .e: a map literal `{key1: val1, key2: val2}`.
  /// The entries are stored as a flat list of
  /// `MapEntry<Expr, Expr>`.
  R visitMapLiteral(MapLiteralExpr e);

  /// .e: a ternary `cond ? then: else`.
  R visitTernary(TernaryExpr e);

  /// .e: a null-coalesce `a ?? b`.
  R visitCoalesce(CoalesceExpr e);

  /// .e: a null-safe member access
  /// `a?.b` (returns `null` if `a` is null).
  R visitNullSafeAccess(NullSafeAccessExpr e);

  /// .d: a navigation reference
  /// `o.customer` (returns the target column
  /// reference, e.g. `c.name`, and signals
  /// that a JOIN must be added).
  R visitNavRef(NavRef e);
}

// ─── Node types ──────────────────────────────────────────────────────

class ConstExpr extends Expr {
  final Object? value;
  const ConstExpr(this.value);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitConst(this);

  @override
  Object? eval(Map<String, Object?> ctx) => value;

  @override
  String toString() {
    if (value == null) return 'null';
    if (value is String) return "'$value'";
    return '$value';
  }
}

class ParamExpr extends Expr {
  final String name;
  const ParamExpr(this.name);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitParam(this);

  @override
  Object? eval(Map<String, Object?> ctx) => ctx[name];

  @override
  String toString() => name;
}

class LambdaExpr extends Expr {
  final List<ParamExpr> params;
  final Expr body;
  const LambdaExpr(this.params, this.body);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitLambda(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    if (params.length == 1) {
      return body.eval({...ctx, params.first.name: ctx[params.first.name]});
    }
    throw UnsupportedError(
      'Multi-parameter lambda eval not implemented in this version. '
      'Only single-parameter lambdas are supported for in-memory eval.',
    );
  }

  @override
  String toString() {
    final ps = params.map((p) => p.name).join(', ');
    return '($ps) => $body';
  }
}

class BinaryExpr extends Expr {
  final String op;
  final Expr left;
  final Expr right;
  const BinaryExpr(this.op, this.left, this.right);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitBinary(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final l = left.eval(ctx);
    final r = right.eval(ctx);
    return switch (op) {
      '+' when l is String || r is String => '$l$r',
      '+' => (l as num) + (r as num),
      '-' => (l as num) - (r as num),
      '*' => (l as num) * (r as num),
      '/' => (l as num) / (r as num),
      '%' => (l as num) % (r as num),
      '==' => l == r,
      '!=' => l != r,
      '<' => (l as num) < (r as num),
      '<=' => (l as num) <= (r as num),
      '>' => (l as num) > (r as num),
      '>=' => (l as num) >= (r as num),
      '&&' => (l as bool) && (r as bool),
      '||' => (l as bool) || (r as bool),
      _ => throw StateError('Unknown binary op: $op'),
    };
  }

  @override
  String toString() => '($left $op $right)';
}

class UnaryExpr extends Expr {
  final String op;
  final Expr operand;
  const UnaryExpr(this.op, this.operand);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitUnary(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final v = operand.eval(ctx);
    return switch (op) {
      '!' => !(v as bool),
      '-' => -(v as num),
      _ => throw StateError('Unknown unary op: $op'),
    };
  }

  @override
  String toString() => '$op($operand)';
}

class MemberAccessExpr extends Expr {
  final Expr target;
  final String name;
  const MemberAccessExpr(this.target, this.name);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitMemberAccess(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final t = target.eval(ctx);
    return MemberAccess.dispatch(t, name);
  }

  @override
  String toString() => '$target.$name';
}

class MethodCallExpr extends Expr {
  final Expr target;
  final String method;
  final List<Expr> args;
  const MethodCallExpr(this.target, this.method, this.args);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitMethodCall(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final t = target.eval(ctx);
    final evaluatedArgs = args.map((a) => a.eval(ctx)).toList();
    return MethodCall.dispatch(t, method, evaluatedArgs);
  }

  @override
  String toString() {
    final as = args.map((a) => '$a').join(', ');
    return '$target.$method($as)';
  }
}

class NullExpr extends Expr {
  const NullExpr();
  @override
  R accept<R>(ExprVisitor<R> v) => v.visitNull(this);
  @override
  Object? eval(Map<String, Object?> ctx) => null;
  @override
  String toString() => 'null';
}

class ListExpr extends Expr {
  final List<Expr> items;
  const ListExpr(this.items);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitList(this);

  @override
  Object? eval(Map<String, Object?> ctx) =>
      items.map((e) => e.eval(ctx)).toList();

  @override
  String toString() {
    final inner = items.map((e) => '$e').join(', ');
    return '[$inner]';
  }
}

// ─── .e: map / ternary / null-aware ─────────────────

/// .e: a map literal
/// `{'a': 1, 'b': 2}`. Stored as a flat list of
/// `MapEntry<Expr, Expr>` for stable ordering and
/// duplicate-key support in the parser.
class MapLiteralExpr extends Expr {
  final List<MapEntry<Expr, Expr>> entries;
  const MapLiteralExpr(this.entries);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitMapLiteral(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final Map<Object, Object?> result = <Object, Object?>{};
    for (final MapEntry<Expr, Expr> e in entries) {
      result[e.key.eval(ctx) as Object] = e.value.eval(ctx);
    }
    return result;
  }

  @override
  String toString() {
    final inner = entries
        .map((MapEntry<Expr, Expr> e) => '${e.key}: ${e.value}')
        .join(', ');
    return '{$inner}';
  }
}

/// .e: a ternary `cond ? then: else`.
class TernaryExpr extends Expr {
  final Expr cond;
  final Expr thenBranch;
  final Expr elseBranch;
  const TernaryExpr(this.cond, this.thenBranch, this.elseBranch);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitTernary(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final Object? c = cond.eval(ctx);
    final bool truthy = c == null ? false : (c is bool ? c : true);
    return truthy ? thenBranch.eval(ctx) : elseBranch.eval(ctx);
  }

  @override
  String toString() => '$cond ? $thenBranch : $elseBranch';
}

/// .e: a null-coalesce `a ?? b`.
class CoalesceExpr extends Expr {
  final Expr left;
  final Expr right;
  const CoalesceExpr(this.left, this.right);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitCoalesce(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final Object? l = left.eval(ctx);
    return l ?? right.eval(ctx);
  }

  @override
  String toString() => '$left ?? $right';
}

/// .e: a null-safe member access `a?.b`.
class NullSafeAccessExpr extends Expr {
  final Expr target;
  final String member;
  const NullSafeAccessExpr(this.target, this.member);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitNullSafeAccess(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    final Object? t = target.eval(ctx);
    if (t == null) return null;
    return _readMember(t, member);
  }

  static Object? _readMember(Object target, String member) {
    // .e: only supports Dart maps for
    // now. For a class instance, the user would
    // use Expr.member which goes through the typed
    // accessor. For in-memory materialisation,
    // nullSafe is typically used on map values.
    if (target is Map) {
      return target[member];
    }
    throw UnsupportedError(
      'NullSafeAccessExpr._readMember: target is ${target.runtimeType}, '
      'expected a Map. For class instances, use Expr.member.',
    );
  }

  @override
  String toString() => '$target?.$member';
}

// ───: aggregate / groupBy / having / join ────────────────

/// An aggregate call: `SUM(x)`, `COUNT(x)`, `AVG(x)`,
/// `MIN(x)`, `MAX(x)`. The [function] is one of
/// `"SUM"`, `"COUNT"`, `"AVG"`, `"MIN"`, `"MAX"`.
/// [distinct] emits `DISTINCT` (`COUNT(DISTINCT x)`).
class AggregateExpr extends Expr {
  final String function;
  final Expr selector;
  final bool distinct;
  const AggregateExpr(this.function, this.selector, {this.distinct = false});

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitAggregate(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    // in-memory eval: fold over the
    // values that [selector] produces for every
    // element in `ctx` (the selector is a LambdaExpr
    // and `ctx` holds its parameter binding).
    final paramName = _selectorParamName(selector);
    final param = ctx[paramName];
    // The `ctx` here is the per-element context: the
    // caller has already evaluated the selector.
    // The in-memory provider folds by iterating
    // the source — we receive the already-
    // selected value as the `param` and reduce
    // accordingly. This is intentionally simple
    // because the LINQ operators have their own
    // fold loops; the Expr-tree eval path is mainly
    // for nested expressions.
    final v = ctx['_value'] ?? param;
    return v;
  }

  String _selectorParamName(Expr s) {
    if (s is LambdaExpr && s.params.isNotEmpty) {
      return s.params.first.name;
    }
    return 'x';
  }

  @override
  String toString() {
    final inner = distinct ? 'DISTINCT $selector' : '$selector';
    return '$function($inner)';
  }
}

/// A `GROUP BY` clause with optional post-aggregation
/// filter (HAVING). In SQL this is
/// `SELECT key[, element] FROM source GROUP BY key [HAVING pred]`.
class GroupByExpr extends Expr {
  final Expr keySelector;
  final Expr? elementSelector;
  final Expr? havingPredicate;
  const GroupByExpr({
    required this.keySelector,
    this.elementSelector,
    this.havingPredicate,
  });

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitGroupBy(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    // In-memory eval of a GroupBy in the expression
    // tree returns the key — actual group iteration
    // happens in the operator, not the eval path.
    return keySelector.eval(ctx);
  }

  @override
  String toString() {
    final sel = elementSelector == null
        ? '$keySelector'
        : '$keySelector, $elementSelector';
    final hav = havingPredicate == null ? '' : ' HAVING $havingPredicate';
    return 'GROUP BY $sel$hav';
  }
}

/// A `HAVING` predicate (post-aggregation filter).
class HavingExpr extends Expr {
  final Expr predicate;
  const HavingExpr(this.predicate);

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitHaving(this);

  @override
  Object? eval(Map<String, Object?> ctx) => predicate.eval(ctx);

  @override
  String toString() => 'HAVING $predicate';
}

/// A `JOIN` clause. The [joinType] is `"INNER"`,
/// `"LEFT"`, `"RIGHT"`, or `"FULL"`.
class JoinExpr extends Expr {
  final Expr outer;
  final Expr inner;
  final Expr outerKey;
  final Expr innerKey;
  final Expr resultSelector;
  final String joinType;
  const JoinExpr({
    required this.outer,
    required this.inner,
    required this.outerKey,
    required this.innerKey,
    required this.resultSelector,
    this.joinType = 'INNER',
  });

  @override
  R accept<R>(ExprVisitor<R> v) => v.visitJoin(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    // In-memory eval of a Join in the expression
    // tree returns the joined result row — actual
    // pair iteration happens in the operator.
    return resultSelector.eval(ctx);
  }

  @override
  String toString() {
    final t = joinType == 'INNER' ? '' : '$joinType ';
    return '${t}JOIN $inner ON $outerKey = $innerKey';
  }
}

// ─── Field / method dispatch ─────────────────────────────────────────

/// Implemented by user models to expose their fields to the
/// expression-tree evaluator.
///
/// In the user writes this by hand (5-line switch). In
/// (`d_rocket_builder`) the codegen will generate it
/// automatically from a `@Table` or `@Model` annotation.
///
/// Example:
///
/// ```dart
/// class User implements RecordLike {
/// final int id;
/// final String name;
/// final int age;
/// final String? email;
///
/// const User({required this.id, ...});
///
/// @override
/// Object? readField(String name) => switch (name) {
/// 'id' => id,
/// 'name' => name,
/// 'age' => age,
/// 'email' => email,
/// _ => null,
/// };
/// }
/// ```
///
/// `Map<String, Object?>` also satisfies the contract — `dispatch`
/// short-circuits before checking for `RecordLike`.
abstract interface class RecordLike {
  /// Returns the value of the field named [name], or `null` if the
  /// field does not exist.
  Object? readField(String name);
}

/// Dispatches a member access (`obj.field`) for the in-memory
/// provider.
class MemberAccess {
  MemberAccess._();

  static Object? dispatch(Object? target, String name) {
    if (target == null) return null;
    if (target is Map<String, Object?>) return target[name];
    if (target is RecordLike) return target.readField(name);
    if (target is String && name == 'length') return target.length;
    return null;
  }
}

/// Dispatches a method call for the in-memory provider. Minimal
/// coverage in; will be extended in .
class MethodCall {
  MethodCall._();

  static Object? dispatch(Object? target, String method, List<Object?> args) {
    if (target is String && method == 'startsWith' && args.length == 1) {
      return target.startsWith(args[0] as String);
    }
    if (target is String && method == 'endsWith' && args.length == 1) {
      return target.endsWith(args[0] as String);
    }
    if (target is String && method == 'contains' && args.length == 1) {
      return target.contains(args[0] as String);
    }
    if (target is String && method == 'toUpperCase' && args.isEmpty) {
      return target.toUpperCase();
    }
    if (target is String && method == 'toLowerCase' && args.isEmpty) {
      return target.toLowerCase();
    }
    if (target is String && method == 'trim' && args.isEmpty) {
      return target.trim();
    }
    if (target is List && method == 'length' && args.isEmpty) {
      return target.length;
    }
    if (target is List && method == 'isEmpty' && args.isEmpty) {
      return target.isEmpty;
    }
    if (target is List && method == 'isNotEmpty' && args.isEmpty) {
      return target.isNotEmpty;
    }
    if (target is List && method == 'join' && args.length == 1) {
      // List.join(separator): mirror the Dart API. The `args`
      // parameter here holds the *evaluated* values, so the
      // separator is a String at this point.
      final sep = args[0];
      if (sep is! String) {
        throw ArgumentError(
          'List.join: separator must be a String, got ${sep.runtimeType}',
        );
      }
      return target.join(sep);
    }
    if (target is String && method == 'isEmpty' && args.isEmpty) {
      return target.isEmpty;
    }
    if (target is String && method == 'isNotEmpty' && args.isEmpty) {
      return target.isNotEmpty;
    }
    throw UnsupportedError(
      'Method "$method" on ${target.runtimeType} is not implemented in '
      'the in-memory provider. Supported: '
      'String.startsWith, endsWith, contains, toUpperCase, toLowerCase, '
      'trim, length, isEmpty, isNotEmpty; '
      'List.length, isEmpty, isNotEmpty, join.',
    );
  }
}

// ─── .d: NavRef (navigation reference) ───────────────

/// .d: an Expr that represents a
/// navigation property reference. The SQL
/// translator sees a `NavRef` and:
/// 1. Emits a column reference for the target
/// table (e.g. `c.name`).
/// 2. Implicitly requires a JOIN to be added
/// to the FROM clause of the outer query
/// (e.g. `INNER JOIN customers c ON c.id = o.customer_id`).
///
/// Example (the closure `(o) => o.customer.name`
/// is translated by the closure translator to):
/// ```dart
/// Expr.binary(
/// '==',
/// Expr.member(Expr.navRef(
/// name: 'customer', // nav name
/// targetTable: 'customers', // target SQL table
/// targetAlias: 'c', // SQL alias for the JOIN
/// fkColumn: 'customer_id', // FK on the source
/// pkColumn: 'id', // PK on the target
///), 'name'),
/// Expr.const_('John'),
///)
/// ```
class NavRef extends Expr {
  /// The name of the navigation property
  /// (e.g. `'customer'`).
  final String name;

  /// The SQL table name of the target entity
  /// (e.g. `'customers'`).
  final String targetTable;

  /// The SQL alias to use in the JOIN
  /// (e.g. `'c'` for `customers c`). When
  /// empty, the translator picks a default
  /// (the first char of the table name,
  /// de-duplicated across the query).
  final String targetAlias;

  /// The FK column on the source entity
  /// (e.g. `'customer_id'` on Order).
  final String fkColumn;

  /// The PK column on the target entity
  /// (e.g. `'id'` on Customer).
  final String pkColumn;

  const NavRef({
    required this.name,
    required this.targetTable,
    this.targetAlias = '',
    required this.fkColumn,
    required this.pkColumn,
  });

  @override
  R accept<R>(ExprVisitor<R> visitor) => visitor.visitNavRef(this);

  @override
  Object? eval(Map<String, Object?> ctx) {
    // .d in-memory eval: read the
    // navigation value from the entity's
    // NavigationRegistry. The closure
    // translator doesn't actually use the
    // closure LINQ on translated trees (it
    // uses the SQL provider) — but the eval
    // is here for the in-memory path (when
    // the user runs the query in Dart).
    final Object? entity = ctx['__self__'];
    if (entity == null) return null;
    return _navLookup?.call(entity, name);
  }

  @override
  String toString() => 'NavRef($name → $targetTable.$pkColumn)';
}

/// .d: a function pointer that the
/// NavigationRegistry sets at startup. Avoids
/// an import cycle between expr.dart and the
/// registry module.
Object? Function(Object entity, String name)? _navLookup;

/// .d: register the navigation lookup
/// function. Called by NavigationRegistry on
/// first use.
void registerNavLookup(Object? Function(Object, String) f) {
  _navLookup = f;
}

// .d: factory for NavRef on the
// Expr namespace. (Sealed classes can't be
// extended from outside, so the factory lives
// here too.)
extension ExprNavRefFactory on Expr {
  /// .d: convenience constructor for
  /// [NavRef]. Use `Expr.navRef(...)` from
  /// user code.
  static NavRef navRef({
    required String name,
    required String targetTable,
    String targetAlias = '',
    required String fkColumn,
    required String pkColumn,
  }) =>
      NavRef(
        name: name,
        targetTable: targetTable,
        targetAlias: targetAlias,
        fkColumn: fkColumn,
        pkColumn: pkColumn,
      );
}
