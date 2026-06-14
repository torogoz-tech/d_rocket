# Layer 3 — LINQ

`IQueryable<T>` is the framework's deferred-execution
queryable. The chain of operators is built up without
materialising intermediate results; a terminal
operator (e.g. `toList`, `firstOrDefault_`, `count_`)
triggers the actual execution. The framework ships
two providers: an in-memory one (over any
`Iterable<T>`) and a SQLite-backed one (over
`DbSet<T>`).

The `IQueryable<T>` API is built on a small
expression-tree DSL called [`Expr`](#the-expr-dsl).
Both providers consume the same tree; the in-memory
provider evaluates it against each element, the SQL
provider translates it to a `WHERE` / `ORDER BY` /
`LIMIT` clause.

---

## Table of contents

- [The underscore convention](#the-underscore-convention)
- [Quickstart](#quickstart)
- [The `IQueryable<T>` interface](#the-iqueryablet-interface)
- [The 40+ operators](#the-40-operators)
- [Two forms: closure vs explicit AST](#two-forms-closure-vs-explicit-ast)
- [The `Expr` DSL](#the-expr-dsl)
- [The visitor pattern](#the-visitor-pattern)
- [Async terminals](#async-terminals)
- [API reference](#api-reference)

---

## The underscore convention

`IQueryable<T>` extends `Iterable<T>`, so the
Dart-core operators (`where`, `take`, `skip`, etc.)
are already there. To avoid clashing, every
`IQueryable<T>` operator uses a **trailing
underscore**:

- `Iterable<T>.where` returns `Iterable<T>` (sync).
- `IQueryable<T>.where_` returns `IQueryable<T>`
  (deferred).

The same convention applies to `take_`, `skip_`,
`orderBy_`, `select_`, `first_`, `firstOrDefault_`,
`single_`, `singleOrDefault_`, etc.

The convention exists because Dart does not allow
method overloading. There is a "clean" (no
underscore) version of `where` on `DbSet<T>` that
acts as a bridge from `DbSet<T>` to
`IQueryable<T>` — see [Layer 4 — ORM](07-layer-4-orm.md).

## Quickstart

```dart
import 'package:d_rocket/d_rocket.dart';

void main() {
  // Lift an Iterable to IQueryable.
  final IQueryable<int> nums = [1, 2, 3, 4, 5].asQueryable;

  // Filter.
  final IQueryable<int> big = nums.where_(
    Expr.lambda(
      <Expr>[Expr.param('n')],
      Expr.binary('>', Expr.param('n'), Expr.const_(2)),
    ),
  );

  // Project.
  final IQueryable<String> words = big.select_<String>(
    Expr.lambda(
      <Expr>[Expr.param('n')],
      Expr.call(Expr.param('n'), 'toString', <Expr>[]),
    ),
  );

  // Materialize.
  final List<String> result = words.toList();
  print(result);  // [3, 4, 5]
}
```

There is no closure-sugar builder in the runtime
(yet — it was removed). The canonical form is the
explicit `Expr.lambda(...)` chain.

## The `IQueryable<T>` interface

```dart
abstract class IQueryable<T> extends Iterable<T> {
  IQueryProvider get provider;
  Expr? get expression;
}
```

A queryable carries two pieces of metadata:
- `provider` — the `IQueryProvider` that will execute
  the query.
- `expression` — the head of the expression tree, or
  `null` for a raw source (e.g. `users.asQueryable`
  with no operator applied).

Most user code never reads these directly; they are
the framework's plumbing.

Lifting a non-queryable `Iterable` to a queryable:

```dart
extension ToQueryableExtension<T> on Iterable<T> {
  IQueryable<T> asQueryable() => EnumerableQuery<T>(this);
}
```

`asQueryable()` is the entry point. The conversion
is cheap — no elements are iterated until a
terminal operator runs.

## The 40+ operators

`IQueryable<T>` ships with around 40 operators
across nine categories. They are implemented as
**extension methods** in `lib/src/linq/operators/`,
one file per category.

### Filter

| Operator | Signature | Behavior |
|---|---|---|
| `where_(predicate)` | `IQueryable<T> where_(Expr predicate)` | Keep elements for which the single-parameter `LambdaExpr` returns `true`. Throws if the predicate is not a `LambdaExpr` with exactly 1 parameter. |
| `ofType_<TResult>()` | `IQueryable<TResult> ofType_<TResult>()` | Keep elements whose runtime type is a subtype of `TResult`. |
| `takeWhile_(predicate)` | `IQueryable<T> takeWhile_(Expr predicate)` | Take from the start while the predicate holds; stop at the first `false` (do not skip the false element). |
| `skipWhile_(predicate)` | `IQueryable<T> skipWhile_(Expr predicate)` | Skip from the start while the predicate holds; keep from the first `false` (include the false element). |

### Project

| Operator | Signature | Behavior |
|---|---|---|
| `select_<TResult>(selector)` | `IQueryable<TResult> select_<TResult>(Expr selector)` | Project each element through a single-parameter `LambdaExpr`. The result type may differ from the source type. |

### Page

| Operator | Signature | Behavior |
|---|---|---|
| `take_(count)` | `IQueryable<T> take_(int count)` | First `count` elements. |
| `skip_(count)` | `IQueryable<T> skip_(int count)` | Skip the first `count` elements. |

### Order

| Operator | Signature | Behavior |
|---|---|---|
| `orderBy_(keySelector)` | `IQueryable<T> orderBy_(Expr keySelector)` | Ascending sort by the selector's value. |
| `orderByDescending_(keySelector)` | `IQueryable<T> orderByDescending_(Expr keySelector)` | Descending sort by the selector's value. |
| `thenBy_(keySelector)` | `IQueryable<T> thenBy_(Expr keySelector)` | Secondary ascending sort. Must follow `orderBy_`, `orderByDescending_`, or another `thenBy_`. Throws if the source is not ordered. |
| `thenByDescending_(keySelector)` | `IQueryable<T> thenByDescending_(Expr keySelector)` | Secondary descending sort. |

The sort materialises the source (no streaming sort
in the in-memory provider). The SQL provider emits
`ORDER BY a ASC, b DESC`.

### Set

| Operator | Signature | Behavior |
|---|---|---|
| `concat_(other)` | `IQueryable<T> concat_(IQueryable<T> other)` | Elements of `this` followed by elements of `other`. |
| `union_(other)` | `IQueryable<T> union_(IQueryable<T> other)` | Set union (deduplicated; preserves first-occurrence order of both sides). |
| `intersect_(other)` | `IQueryable<T> intersect_(IQueryable<T> other)` | Set intersection. |
| `except_(other)` | `IQueryable<T> except_(IQueryable<T> other)` | Set difference. |
| `distinct_()` | `IQueryable<T> distinct_()` | Deduplicate (using Dart's `==` / `hashCode`). |

### Quantifier

| Operator | Signature | Behavior |
|---|---|---|
| `any_({where})` | `bool any_({Expr? where})` | `true` if at least one element exists, or if at least one element satisfies the optional `where` predicate. Short-circuits. |
| `all_(predicate)` | `bool all_(Expr predicate)` | `true` if every element satisfies the predicate. Vacuously true for empty source. Short-circuits. |
| `contains_(value)` | `bool contains_(T value)` | `true` if `value` is an element of the source (using `==` / `hashCode`). |

The `any_` two-form dispatch is via the `where:`
named parameter, because Dart does not allow method
overloading.

### Aggregate

| Operator | Signature | Behavior |
|---|---|---|
| `count_({where})` | `int count_({Expr? where})` | Number of elements. With `where:`, counts only those matching. |
| `longCount_({where})` | `int longCount_({Expr? where})` | Same as `count_` (kept for C# naming parity; on the Dart VM `int` is 64-bit so there is no overflow risk). |
| `sum_(selector)` | `num sum_(Expr selector)` | Sum of selector values. Selector must return `num` (int or double). Returns `0` for empty source. |
| `average_(selector)` | `double average_(Expr selector)` | Arithmetic mean. Throws `StateError` on empty source. |
| `min_(selector)` | `Object? min_(Expr selector)` | Smallest value. Throws `StateError` on empty source. |
| `max_(selector)` | `Object? max_(Expr selector)` | Largest value. Throws `StateError` on empty source. |
| `aggregate_<TResult>({seed, func})` | `TResult aggregate_<TResult>({required TResult seed, required Expr func})` | Custom reduction. `func` is a 2-parameter `LambdaExpr` `(acc, x) => nextAcc`. |

### Element

| Operator | Signature | Behavior |
|---|---|---|
| `first_({where})` | `T first_({Expr? where})` | First element. Throws `StateError` if empty. |
| `firstOrDefault_({where})` | `T? firstOrDefault_({Expr? where})` | First element or `null`. |
| `single_({where})` | `T single_({Expr? where})` | Exactly one element. Throws if 0 or 2+. |
| `singleOrDefault_({where})` | `T? singleOrDefault_({Expr? where})` | Zero or one element, else `null`. Throws if 2+. |
| `elementAt_(index)` | `T elementAt_(int index)` | Element at `index`. Throws `RangeError` on out-of-range. |
| `elementAtOrDefault_(index)` | `T? elementAtOrDefault_(int index)` | Element at `index`, or `null`. |

The `first_` and `single_` (and `*OrDefault` variants)
use a named `where:` parameter to disambiguate the
no-arg and predicate forms.

### Convert

| Operator | Signature | Behavior |
|---|---|---|
| `toList_()` | `List<T> toList_()` | Materialise as a `List<T>`. (Kept for C# naming parity with `Iterable.toList`.) |
| `toSet_()` | `Set<T> toSet_()` | Materialise as a `Set<T>`. |
| `toMap_<TKey>({keySelector})` | `Map<TKey, T> toMap_<TKey>({required Expr keySelector})` | Materialise as a `Map<TKey, T>`. Throws `StateError` on duplicate keys. |
| `asEnumerable_()` | `Iterable<T> asEnumerable_()` | Re-cast as a plain `Iterable<T>`. Useful at the boundary with `dart:core` collection APIs. |
| `cast_<TResult>()` | `IQueryable<TResult> cast_<TResult>()` | Cast each element to `TResult`. Throws `TypeError` on mismatch. |

### Group & join

| Operator | Signature | Behavior |
|---|---|---|
| `groupBy_<TKey>({keySelector})` | `IQueryable<IGrouping<TKey, T>> groupBy_<TKey>({required Expr keySelector})` | Group by selector. The result is an `IQueryable<IGrouping<TKey, T>>`. Each `IGrouping` exposes `key` and is iterable over its elements. |
| `join_<TInner, TKey, TResult>({inner, outerKeySelector, innerKeySelector, resultSelector})` | `IQueryable<TResult> join_<...>(...)` | INNER JOIN. `resultSelector` is a 2-parameter `LambdaExpr` `(outer, inner) => result`. |
| `groupJoin_<TInner, TKey, TResult>({inner, outerKeySelector, innerKeySelector, resultSelector})` | `IQueryable<TResult> groupJoin_<...>(...)` | LEFT OUTER JOIN. `resultSelector` is a 3-parameter `LambdaExpr` `(outer, inners, key) => result` where `inners` is a `List<TInner>`. |

### Lookup

| Operator | Signature | Behavior |
|---|---|---|
| `toLookup_<TKey>({keySelector})` | `ILookup<TKey, T> toLookup_<TKey>({required Expr keySelector})` | Build a multi-valued dictionary. The result is `ILookup<TKey, T>` with `containsKey`, `operator []` (returns empty iterable for missing keys), `keys`, and `length`. |

`ILookup` is the `toDictionary` / `toLookup` of C#
LINQ — like a `Map<TKey, List<T>>` with explicit
"key may map to zero values" semantics.

## Two forms: closure vs explicit AST

Every LINQ operator in d_rocket (with the lone
exception of the terminal aggregates `count_` and
`firstOrDefault_`) accepts **two equivalent
forms** for its predicate / selector arguments:

- **Closure** — a Dart function, written with the
  usual `=>` arrow syntax. Idiomatic, 99% of
  user code.
- **AST** — an `Expr` value, built explicitly with
  the [`Expr` DSL](#the-expr-dsl) factories. Used
  for dynamic queries, unit tests of the SQL
  translator, and the codegen that produces query
  helpers for `@Table`-annotated classes.

You can mix the two in the same chain — `where_`
can be AST and `orderBy_` can be a closure, or
vice versa. The dispatch is done at runtime, per
operator.

### Side-by-side

| Operator | Closure (idiomatic) | AST (explicit) |
|---|---|---|
| `where_` | `.where_((b) => b.name == 'Name')` | `.where_(Expr.lambda([Expr.param('b')], Expr.binary('==', Expr.member(Expr.param('b'), 'name'), Expr.const_('Name'))))` |
| `select_<T2>` | `.select_<String>((b) => b.title)` | `.select_<String>(Expr.lambda([Expr.param('b')], Expr.member(Expr.param('b'), 'title')))` |
| `orderBy_` / `orderByDescending_` | `.orderByDescending_((b) => b.price)` | `.orderByDescending_(Expr.lambda([Expr.param('b')], Expr.member(Expr.param('b'), 'price')))` |
| `take_` / `skip_` | AST-only (these are SQL-only pagination, not selectors) | `.take_(3)`, `.skip_(10)` |
| `groupBy_<TKey>` | `.groupBy_<int>(keySelector: (b) => b.authorId)` | `.groupBy_<int>(keySelector: Expr.lambda([Expr.param('b')], Expr.member(Expr.param('b'), 'authorId')))` |
| `join_<TIn,TKey,TR>` | `.join_<Author,int,String>(inner: q, outerKeySelector: (b) => b.authorId, innerKeySelector: (a) => a.id, resultSelector: (b, a) => '${a.name}: ${b.title}')` | (all three selectors as `Expr.lambda(...)`) |
| `groupJoin_<...>` | (same shape, three closures) | (all three selectors as `Expr.lambda(...)`) |
| `sum_` / `average_` | `.sum_((b) => b.price)`, `.average_((b) => b.price)` | `.sum_(Expr.lambda([Expr.param('b')], Expr.member(Expr.param('b'), 'price')))` |
| `min_` / `max_` | `.min_((b) => b.year)`, `.max_((b) => b.price)` | (AST form, same shape) |

### When to use which

| Scenario | Recommended form |
|---|---|
| Hand-written application code | **Closure** — it's Dart. |
| Unit-testing the SQL translator | **AST** — you need precise control over the tree shape, the closure form would hide the test. |
| Building a dynamic query (e.g. a REST `?filter=` parser) | **AST** — the field, operator, and value all come from strings, not a literal closure. |
| Codegen (`d_rocket_builder` generating helpers for `@Table` classes) | **AST** — the generator emits the tree literally. |
| Composing operators across two libraries that don't share a codegen | **Closure** — no interop cost, no DSL to learn. |

### Why both forms exist — the technical decision

There are three reasons d_rocket carries both the
closure form and the AST form, instead of one or
the other:

1. **The closure is what users want to write.** Dart
   programmers reach for `(b) => b.name == 'Name'`
   the same way they reach for `if` and `for`. The
   closure is the path that is *idiomatic*. Forcing
   everyone to learn an AST DSL just to filter a
   list would put d_rocket in the same bucket as
   the JPA Criteria API — useful, but not fun. The
   closure form makes the public surface
   indistinguishable from `Iterable.where`.

2. **The AST is what the SQL provider needs.** The
   in-memory provider could evaluate a closure
   trivially, but the SQLite provider must
   *translate* the predicate to SQL. It cannot
   read a Dart function's bytecode. It needs a
   *tree* — `b.name == 'Name'` becomes
   `Lambda([Param('b')], Binary('==', Member(Param('b'), 'name'), Const('Name')))`. The
   AST is the canonical, provider-agnostic
   representation; the closure is sugar on top.

3. **Some queries are not expressible as a closure.**
   A REST API that takes a `?filter=name:eq:John`
   query string cannot turn that into a literal
   `(b) => b.name == 'John'` at parse time — the
   field, operator, and value are all runtime data.
   The AST is the only representation that lets
   you build the query programmatically. The same
   is true for any sort of query-builder UI.

The design choice, then, is:

- The **closure** is the user-facing syntax sugar.
  When the operator sees a closure, it materialises
  the source (running the same `where_` / `orderBy_` /
  `take_` / `skip_` pipeline up to this point) and
  then runs the closure in Dart over the surviving
  rows. There is no SQL translation cost — the
  closure is plain Dart. The trade-off is that the
  closure path cannot be pushed down to SQLite
  (e.g. for `where_`); the source query has to
  fully materialise first.

- The **AST** is the provider-facing canonical
  form. When the operator sees an `Expr`, it asks
  the current `IQueryProvider` to translate the
  `Expr` to a `SqlFragment` and splices that into
  the SQL `WHERE` / `ORDER BY` / `LIMIT` clause.
  The trade-off is the verbosity of building the
  tree by hand.

Both forms are first-class: every operator does
the same type check at the call site, both
compose with each other in the same chain, and
both participate in deferred execution. The
choice is yours, per operator, per query.

### Operator dispatch rules

When the operator runs, it does a runtime `is`
check on the argument:

```dart
Queryable<T> where_(Object predicate) {
  if (predicate is bool Function(T)) {
    // Closure path: stash in _memFilters,
    // applied after SQL in _materialize().
  }
  if (predicate is Expr) {
    // AST path: stash in _where, translated
    // to a SQL fragment in _buildSelect().
  }
  throw ArgumentError(
    'where_ expects bool Function(T) or Expr, '
    'got ${predicate.runtimeType}',
  );
}
```

The exception is `join_` and `groupJoin_`, which
take three selectors and require *all three* to be
closures or *all three* to be `Expr` (no mixing
within a single call). This is checked at the
constructor of the internal `_JoinOp` class.

### The closure-form gotcha: explicit parameter types

Because every operator signature accepts `Object`
(not a function type), Dart's closure type
inference has no information about the row type.
This means a closure written as `(u) => u.year > 1970`
is inferred as `(dynamic) => dynamic`, which does
not match the `is bool Function(Book)` check at
runtime — it falls through to the AST path, which
then throws.

**The fix is to type the closure parameter
explicitly**:

```dart
// Does NOT match the closure overload — type is
// `(dynamic) => dynamic`:
.where_((u) => u.year > 1970)

// Does match — type is `bool Function(Book)`:
.where_((Book u) => u.year > 1970)
```

This is the same rule that C# applies to its
`Expression<Func<T,bool>>` vs `Func<T,bool>`
overloads, and the same rule that LINQ-to-SQL
used to require. The verbose annotation is the
price of supporting both forms through a single
`Object` parameter; the alternative — a separate
method name for each form, like `whereExpr_` and
`whereLambda_` — was considered and rejected
because it would double the surface area of the
API.

For the `groupJoin_` result selector the runtime
type check on the `matches` list (a `List<dynamic>`)
can also fail when the user types the second
parameter as `Iterable<Book>`. In that case, drop
the explicit type annotation on the matches
parameter and let Dart infer `dynamic`; the
closure body still type-checks each element when
it accesses `b.title`.

---

## The `Expr` DSL

The `Expr` class is the canonical query language.
It's a sealed root with a set of static factory
methods and concrete subclasses for each node type.

```dart
sealed class Expr {
  const Expr();
  R accept<R>(ExprVisitor<R> visitor);
  Object? eval(Map<String, Object?> ctx);
  String toString();

  // ─── Static factories ──────────────────────────────────────

  static const Expr null_;                                 // The constant `null`.
  static Expr const_(Object? value);                      // Any constant value.
  static Expr param(String name);                         // A parameter reference.
  static Expr lambda(List<Expr> params, Expr body);       // A lambda.
  static Expr binary(String op, Expr left, Expr right);   // Binary op: + - * / % == != < <= > >= && ||.
  static Expr unary(String op, Expr operand);             // Unary op: ! -.
  static Expr member(Expr target, String name);           // Field access: target.name.
  static Expr call(Expr target, String method, List<Expr> args);  // Method call.
  static Expr list(List<Expr> items);                     // List literal.
  static Expr map(List<MapEntry<Expr, Expr>> entries);    // Map literal.
  static Expr ternary({required Expr cond, required Expr thenBranch, required Expr elseBranch});  // `cond ? a : b`.
  static Expr coalesce(Expr left, Expr right);            // `a ?? b`. Translates to SQL `COALESCE`.
  static Expr nullSafe(Expr target, String member);       // `a?.b`. Translates to SQL via `CASE WHEN a IS NULL THEN NULL ELSE …`.
  static Expr aggregate(String function, {required Expr selector, bool distinct = false});
  static Expr groupBy({required Expr keySelector, Expr? elementSelector, Expr? havingPredicate});
  static Expr having(Expr predicate);
  static Expr join({required Expr outer, required Expr inner, required Expr outerKey, required Expr innerKey, required Expr resultSelector, String joinType = 'INNER'});
}
```

### Concrete node types

| Type | Holds | Built by |
|---|---|---|
| `ConstExpr` | `Object? value` | `Expr.const_(value)` |
| `ParamExpr` | `String name` | `Expr.param('u')` |
| `LambdaExpr` | `List<ParamExpr> params, Expr body` | `Expr.lambda([...], body)` |
| `BinaryExpr` | `String op, Expr left, Expr right` | `Expr.binary('==', left, right)` |
| `UnaryExpr` | `String op, Expr operand` | `Expr.unary('!', operand)` |
| `MemberAccessExpr` | `Expr target, String name` | `Expr.member(target, 'name')` |
| `MethodCallExpr` | `Expr target, String method, List<Expr> args` | `Expr.call(target, 'name', [...])` |
| `NullExpr` | (singleton) | `Expr.null_` |
| `ListExpr` | `List<Expr> items` | `Expr.list([...])` |
| `MapLiteralExpr` | `List<MapEntry<Expr, Expr>>` | `Expr.map([MapEntry(...)...])` |
| `TernaryExpr` | `cond, thenBranch, elseBranch` | `Expr.ternary({...})` |
| `CoalesceExpr` | `left, right` | `Expr.coalesce(left, right)` |
| `NullSafeAccessExpr` | `target, member` | `Expr.nullSafe(target, 'member')` |
| `AggregateExpr` | `function, selector, distinct` | `Expr.aggregate('sum', selector: ...)` |
| `GroupByExpr` | `keySelector, elementSelector, havingPredicate` | `Expr.groupBy({...})` |
| `HavingExpr` | `predicate` | `Expr.having(predicate)` |
| `JoinExpr` | `outer, inner, outerKey, innerKey, resultSelector, joinType` | `Expr.join({...})` |

### Examples

```dart
// (u) => u.age >= 18
Expr.lambda(
  <Expr>[Expr.param('u')],
  Expr.binary('>=',
    Expr.member(Expr.param('u'), 'age'),
    Expr.const_(18)),
);

// (u) => u.name.toUpperCase()
Expr.lambda(
  <Expr>[Expr.param('u')],
  Expr.call(Expr.member(Expr.param('u'), 'name'), 'toUpperCase', <Expr>[]),
);

// (u) => u.discount ?? 0
Expr.lambda(
  <Expr>[Expr.param('u')],
  Expr.coalesce(
    Expr.member(Expr.param('u'), 'discount'),
    Expr.const_(0)),
);

// (u) => u.discount != null ? u.discount : 0
Expr.lambda(
  <Expr>[Expr.param('u')],
  Expr.ternary(
    cond: Expr.binary('!=',
      Expr.member(Expr.param('u'), 'discount'),
      Expr.null_),
    thenBranch: Expr.member(Expr.param('u'), 'discount'),
    elseBranch: Expr.const_(0),
  ),
);

// (u) => u?.address?.city
Expr.lambda(
  <Expr>[Expr.param('u')],
  Expr.nullSafe(
    Expr.nullSafe(Expr.param('u'), 'address'),
    'city'),
);
```

## The visitor pattern

`Expr` is a sealed class. Both providers consume the
tree through the `ExprVisitor<R>` interface:

```dart
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
  R visitMapLiteral(MapLiteralExpr e);
  R visitTernary(TernaryExpr e);
  R visitCoalesce(CoalesceExpr e);
  R visitNullSafeAccess(NullSafeAccessExpr e);
  R visitNavRef(NavRef e);
}
```

The in-memory provider uses `Expr.eval(ctx)` directly
(the tree self-evaluates). The SQL provider writes
a `SqlTranslator` visitor that walks the tree and
emits SQL fragments.

External visitors (for codegen, IDE tooling, custom
backends) extend `ExprVisitor<R>` and call
`expr.accept(this)`.

## Async terminals

There are no `*Async_` variants of the terminals.
`IQueryable<T>` is synchronous by design; the
deferred-execution semantics assume a non-async
chain. If you need async iteration, use
`Stream<T>.fromIterable(queryable)` or `for await`
over the underlying `DbSet<T>` (which is async via
the SQLite layer).

This is by design: the LINQ chain composes
synchronously, and the underlying provider is
responsible for any I/O. The in-memory provider
doesn't need async; the SQLite provider does its
async work in `toList()` / `first_()` / etc. by
flushing the query and materialising the result.

## API reference

### `IQueryable<T>`

Abstract queryable interface. Extends `Iterable<T>`.
Two getters: `provider`, `expression`.

### `IQueryProvider`

Abstract backend. Methods: `createQuery<T>(Expr)`,
`execute<TResult>(Expr)`.

### `Expr` and the 18 concrete node types

See [The Expr DSL](#the-expr-dsl) above.

### `ExprVisitor<R>`

External visitor. One `visit*` method per node type.

### `IGrouping<TKey, T>`

Result of `groupBy_`. Extends `Iterable<T>`, has
`key` and `length` fields.

### `ILookup<TKey, TElement>`

Result of `toLookup_`. Extends
`Iterable<IGrouping<TKey, TElement>>`, has
`containsKey`, `operator []`, `keys`, `length`.

### `asQueryable()` extension

Lifts an `Iterable<T>` to `IQueryable<T>`. The
conversion is cheap — no elements are iterated
until a terminal runs.

### The 40+ operators

See [The 40+ operators](#the-40-operators) above.
All operators are extension methods on
`IQueryable<T>`, in one file per category under
`lib/src/linq/operators/`.
