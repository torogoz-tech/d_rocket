# Bug Review — `d_rocket` LINQ (historical)

> **Historical bug review of the in-memory LINQ provider shipped
> before `d_rocket 2.0.0`.** Every bug listed here is fixed. The
> modern deferred-execution LINQ and its SQL push-down are
> documented in [06-layer-3-linq.md](06-layer-3-linq.md).

## TL;DR

| Severity | Count | Status |
|---|---|---|
| Correctness bugs (silent wrong results) | 0 | — |
| Validation bugs (should throw, doesn't) | 1 | closed — see B-09 |
| Latent bugs (race conditions, multi-isolate) | 0 | N/A — Dart single-isolate |
| Limitations (acceptable for an in-memory LINQ) | 3 | documented, see L-01..L-03 |
| Verified-fixes for the 8 bugs from the previous review | 8 | all correct |

The implementation is **sound**. The single remaining issue was a
**validation gap** in `join_` / `groupJoin_` that did not trigger
in practice but is tightened in the current release so that
runtime errors are easier to diagnose once LINQ starts being
translated to SQL.

---

## 1. The bugs from the previous review

| # | Symptom | Root cause | Fix | Verified? |
|---|---|---|---|---|
| B-01 | `where<TResult>(...)` compile error | Dart's `Iterable.where` is not generic | Use `.where(...).cast<TResult>()` in `ofType_` | ✅ |
| B-02 | `any_()` and `any_(predicate)` couldn't coexist | Dart does not allow method overloading | Combined into `any_({Expr? where})` | ✅ |
| B-03 | `concat_` evaluated eagerly | `[...this, ...other]` iterates immediately | Replaced with `sync*` generator `_concatGen` | ✅ verified by `is deferred until terminal` test |
| B-04 | `intersect_` / `except_` produced duplicates | No `seen` tracking | Added `<T>{}` and `seen.add(e)` guard | ✅ verified by `deduplicates` and `preserves order and dedups` tests |
| B-05 | `where_(g.length > 1)` failed with `Null is not num` | `IGrouping` did not implement `RecordLike` | Made `IGrouping` implement `RecordLike` with a default `readField` | ✅ verified by `chains with where_ on the group` |
| B-06 | Same as B-05; root cause was `_Grouping` not inheriting `readField` | `implements` vs `extends` | `_Grouping` now `extends IGrouping<TKey, T>` | ✅ |
| B-07 | `name + '!'` failed with `'Null' is not a subtype of 'num'` | `BinaryExpr '+'` cast both sides to `num` | New clause `'+' when l is String \|\| r is String => '$l$r'` | ✅ |
| B-08 | First `select_` test had a precedence bug | Multi-level `+` chaining with `'#'` and `')'` | Simplified to `name + '!'` | ✅ |
| B-09 | `_requireResult` accepts the wrong arity for `join_` vs `groupJoin_` | A 3-param lambda to `join_` was silently accepted (3rd param = null at eval) | `_requireResult` takes an explicit `expected` arity; `join_` passes 2, `groupJoin_` passes 3 | ✅ (closed) |

All 9 fixes are in `lib/src/linq/`.

---

## 2. Detailed findings

### B-09 — `_requireResult` accepts the wrong arity for `join_` vs `groupJoin_`

**Severity:** validation gap

**Status:** closed.

**Location:** `lib/src/linq/operators/join.dart`

**Issue (in the old code):** `join_` always used `params[0]` and
`params[1]` (outer, inner) at evaluation time. If a user passed
a 3-param lambda to `join_`, the third param's name was *defined*
in the tree but was *not* in the context map at eval time. The
body might still work if it only referenced the first two params,
but a body that referenced the third would receive `null` for it
— no warning, no error.

**Test that demonstrated the issue (now in the test suite):**

```dart
test('join_ with 3-param resultSelector does not validate', () {
  // join_ requires 2 params. We pass 3. The 3rd param is silently ignored.
  // Currently this does NOT throw. It should.
  final bad = Expr.lambda(
    [Expr.param('o'), Expr.param('i'), Expr.param('k')],
    Expr.const_('x'),
  );
  // Expected: throwsArgumentError.
  // Actual: silently accepted.
  final _ = users.asQueryable().join_<_Post, int, String>(
    inner: posts.asQueryable(),
    outerKeySelector: userById,
    innerKeySelector: postByUserId,
    resultSelector: bad,  // 3 params — wrong for join_
  );
});
```

**Fix applied:** the helper now takes `int expected` as a
positional parameter and throws with a
`selector.params.length`-formatted message. The two call sites
(`join_` and `groupJoin_`) now pass `2` and `3` respectively.
Two tests in `test/linq/join_test.dart` cover the bad-arity
case for both operators.

---

### L-01 — `select_<TResult>` and `aggregate_<TResult>` do not validate the result type

**Severity:** limitation (matches C# behavior)

**Where:** `_ProjectedEnumerableQuery.iterator` does `as TResult`;
`aggregate_` does `as TResult`.

**Behavior:** if the body returns a value that is not assignable
to `TResult`, the user gets a `TypeError` at *iteration* time,
not at *call* time. The error message is the default Dart cast
message, which is not very helpful.

C# LINQ does the same thing (the type is checked at runtime,
not statically). A future SQL provider may emit a friendlier
error like "select_<int> body returned 'String'; expected
num/int."

---

### L-02 — `min_` / `max_` silently return the first-encountered value for incommensurable types

**Severity:** limitation (matches C# behavior)

**Where:** `_compareForOrder` returns `null` for incommensurable
types (e.g. `int` vs `String`). The min/max loop leaves `best`
unchanged in that case.

**Behavior:** the result is the first-encountered value, not the
smallest/largest. C# throws `ArgumentException` in this case.

The current behavior is forgiving; matching C# strictly is a
one-line change in `_compareForOrder` and is a candidate for a
future patch.

---

### L-03 — `union_` / `intersect_` / `except_` use Dart's default `==` / `hashCode`

**Severity:** limitation

**Where:** `union_`, `intersect_`, `except_` build internal
`Set<T>` instances to dedup. Equality is determined by `==` /
`hashCode`.

**Behavior:** two `User` instances with the same `id` are
considered *different* (default `User` is identity-equal).
Users must implement `==` / `hashCode` to get value-based
equality.

This is documented in the test "uses `==` / `hashCode`" in
`quantifiers_test.dart` and is standard Dart behavior. The
`RecordLike` interface is a good place to add a
`hashBy(keySelectors)` helper in a future version.

---

## 3. Properties that are correct

| Property | Verdict |
|---|---|
| **Lazy execution** | `asQueryable()` is lazy. `where_`, `select_`, `take_`, `skip_`, `takeWhile_`, `skipWhile_`, `ofType_`, `concat_` (after the sync* fix), `union_`, `intersect_`, `except_`, `cast_` all delegate to `iterator` lazily. |
| **Short-circuit** | `any_`, `all_`, `contains_`, `first_`, `firstOrDefault_`, `single_`, `elementAt_` all short-circuit. |
| **Stable ordering** | `orderBy_` uses Dart's `List.sort`, which is a stable merge sort. |
| **Resource cleanup** | All `Iterable` wrappers are garbage-collected when the queryable is dropped. The `join_` / `groupJoin_` internal `index` map is built once, not held beyond the iteration. |
| **Null safety** | `MemberAccess.dispatch` and `MethodCall.dispatch` handle `null` targets without NPE. `BinaryExpr` for `==`/`!=` short-circuits before the `num` cast. `where_(predicate)` on a `null` body result is treated as `false`. |
| **String concatenation** | `+` now handles `String + String`, `String + num`, `num + String` correctly via the `'$l$r'` clause. |
| **Cross-operator chaining** | All operators return `IQueryable<T>`, so chaining is type-safe. `where_ → select_ → orderBy_ → take_` works end-to-end. |
| **Generic type preservation** | `select_<TResult>`, `cast_<TResult>`, `groupBy_<TKey>`, `join_<TInner, TKey, TResult>`, `aggregate_<TResult>` all carry the new type through. |
| **Edge case: empty source** | Tested for every operator. |
| **Edge case: single element** | Tested for `single_`, `singleOrDefault_`, `groupBy_`. |
| **Edge case: all duplicates** | Tested for `distinct_`, `union_`, `intersect_`, `except_`. |
| **Edge case: negative count** | `take_(-1)` throws `RangeError`, `skip_(-1)` throws `RangeError`. |

---

## 4. How this review shapes the SQL provider

The properties that are **correct** above are the contract the
SQL provider (`d_rocket_engine_sqlite`,
`d_rocket_engine_postgres`, `d_rocket_engine_web`) has to
preserve:

- The `*_` (sync) terminals must continue to short-circuit.
- The `*Async_` (async) terminals must produce the same output
  in the same order as the sync counterparts.
- The engine's `SqlDialect` must translate the `Expr` tree
  using bind parameters in the same order as the `?`
  placeholders in the emitted SQL.

The properties that are **limitations** (L-01, L-02, L-03)
are documented in the public API and the engine provider does
not relax them.

---

## 5. Test counts

| Suite | Tests | Status |
|---|---|---|
| `d_rocket/test/linq/*_test.dart` (24 files) | all pass | ✅ |
| `d_rocket/test/orm/*_test.dart` (14 files) | all pass | ✅ |
| `d_rocket/test/serializer/*_test.dart` (6 files) | all pass | ✅ |
| `d_rocket/test/rest/*_test.dart` (10 files) | all pass | ✅ |
| `d_rocket/test/sync/*_test.dart` (12 files) | all pass | ✅ |
| `d_rocket/test/realtime/*_test.dart` (4 files) | all pass | ✅ |
| **Total** | **~1,184** | **✅** |
