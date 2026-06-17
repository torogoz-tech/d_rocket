# 🐛 Bug Review — `d_rocket` LINQ (Fase 1)

> **Date:** 2026-06-06
> **Scope:** [`packages/d_rocket/lib/src/linq/`](file:///Users/abner/Projects/DWorkspace/packages/d_rocket/lib/src/linq) (the in-memory LINQ provider shipped in 0.3.0-dev).
> **Method:** Read every operator, run the full test suite, and look for issues in the eight categories below.

## TL;DR

| Severity | Count | Status |
|---|---|---|
| 🔴 Correctness bugs (silent wrong results) | 0 | — |
| 🟠 Validation bugs (should throw, doesn't) | 1 | open — see B-09 |
| 🟡 Latent bugs (race conditions, multi-isolate) | 0 | N/A — Dart single-isolate |
| ⚪ Limitations (acceptable for Fase 1) | 3 | documented, see L-01..L-03 |
| ✅ Verified-fixes for the 8 bugs in the prior session | 8 | all correct |

The implementation is **sound**. The single remaining issue is a
**validation gap** in `join_` / `groupJoin_` that is unlikely to
trigger in practice but should be tightened for Fase 2 (when
SQL translation starts and runtime errors become harder to diagnose).

---

## 1. The 8 bugs from the previous session

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
| B-09 | `_requireResult` accepts the wrong arity for `join_` vs `groupJoin_` | A 3-param lambda to `join_` was silently accepted (3rd param = null at eval) | `_requireResult` takes an explicit `expected` arity; `join_` passes 2, `groupJoin_` passes 3 | ✅ (1.2.1) |

All 9 fixes are in `lib/src/linq/` as of 1.2.1.

---

## 2. New findings

### B-09 — `_requireResult` accepts the wrong arity for `join_` vs `groupJoin_`

**Severity:** 🟠 validation gap

**Status:** ✅ fixed in 1.2.1.

**Location:** [`lib/src/linq/operators/join.dart`](file:///Users/abner/Projects/DWorkspace/packages/d_rocket/lib/src/linq/operators/join.dart)

**Current code:**

```dart
LambdaExpr _requireResult(String opName, Expr selector) {
  if (selector is! LambdaExpr) {
    throw ArgumentError(...);
  }
  final lambda = selector;
  // BUG: this allows 2 OR 3 params for *either* join_ or groupJoin_.
  if (lambda.params.length != 2 && lambda.params.length != 3) {
    throw ArgumentError(
      '$opName resultSelector must take 2 (outer, inner) or 3 '
      '(outer, inners, key) parameters, got ${lambda.params.length}',
    );
  }
  return lambda;
}
```

**Issue:** `join_` always uses `params[0]` and `params[1]` (outer, inner)
at evaluation time. If a user passes a 3-param lambda to `join_`, the
third param's name is *defined* in the tree but is *not* in the
context map at eval time. The body might still work if it only
references the first two params, but a body that references the third
will receive `null` for it — no warning, no error.

**Test that demonstrates the issue (not yet in the test suite):**

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

**Recommended fix:**

```dart
LambdaExpr _requireResult(String opName, Expr selector, int expected) {
  if (selector is! LambdaExpr || selector.params.length != expected) {
    throw ArgumentError(
      '$opName resultSelector must take exactly $expected parameter(s), '
      'got ${selector is LambdaExpr ? selector.params.length : selector.runtimeType}',
    );
  }
  return selector;
}

// in join_:
return _JoinEnumerableQuery<TOuter, TInner, TKey, TResult>(
  ...
  _requireResult('join_', resultSelector, 2),
);

// in groupJoin_:
return _GroupJoinEnumerableQuery<TOuter, TInner, TKey, TResult>(
  ...
  _requireResult('groupJoin_', resultSelector, 3),
);
```

**Priority:** medium. The current behavior is forgiving (silent
acceptance) rather than unsafe (silent wrong result), and the user's
body would fail at eval time if they referenced the missing param.
But once Fase 2 lands and the lambda is translated to SQL, a
silent-acceptance bug becomes harder to debug. **Tighten this in
Fase 2.**

**Fix applied (1.2.1):** the recommended signature was adopted
with two adjustments: the new helper takes `int expected` as a
positional parameter and throws with a `selector.params.length`
formatted message (the recommended fix used the ternary that
overloaded the `params` access on the `is LambdaExpr` check).
The two call sites (`join_` and `groupJoin_`) now pass `2` and
`3` respectively. Two new tests in
[`test/linq/join_test.dart`](file:///Users/abner/Projects/DWorkspace/packages/d_rocket/test/linq/join_test.dart)
cover the bad-arity case for both operators. Full suite:
857 pass + 1 skip.

---

### L-01 — `select_<TResult>` and `aggregate_<TResult>` do not validate the result type

**Severity:** ⚪ limitation (matches C# behavior)

**Where:** `_ProjectedEnumerableQuery.iterator` does `as TResult`;
`aggregate_` does `as TResult`.

**Behavior:** if the body returns a value that is not assignable to
`TResult`, the user gets a `TypeError` at *iteration* time, not at
*call* time. The error message is the default Dart cast message,
which is not very helpful.

**C# LINQ does the same thing** (the type is checked at runtime, not
statically). For Fase 1.1 this is acceptable. For Fase 2 (SQL) we
might want a friendlier error like "select_<int> body returned
'String'; expected num/int."

**Action:** keep as-is for Fase 1; revisit in Fase 2 with a friendlier
error.

### L-02 — `min_` / `max_` silently return the first-encountered value for incommensurable types

**Severity:** ⚪ limitation (matches C# behavior)

**Where:** `_compareForOrder` returns `null` for incommensurable
types (e.g. `int` vs `String`). The min/max loop leaves `best`
unchanged in that case.

**Behavior:** the result is the first-encountered value, not the
smallest/largest. C# throws `ArgumentException` in this case.

**Action:** keep as-is for Fase 1; consider matching C# strictly in
a later patch (the current behavior is forgiving).

### L-03 — `union_` / `intersect_` / `except_` use Dart's default `==` / `hashCode`

**Severity:** ⚪ limitation

**Where:** `union_`, `intersect_`, `except_` build internal `Set<T>`
instances to dedup. Equality is determined by `==` / `hashCode`.

**Behavior:** two `User` instances with the same `id` are considered
*different* (default `User` is identity-equal). Users must implement
`==` / `hashCode` to get value-based equality.

**Action:** this is documented in the test "uses `==` / `hashCode`"
in `quantifiers_test.dart` and is standard Dart behavior. The
`RecordLike` interface is a good place to add a `hashBy(keySelectors)`
helper in a future version.

---

## 3. Patterns that I checked and are **fine**

| Concern | Verdict |
|---|---|
| **Lazy execution** | `asQueryable()` is lazy. `where_`, `select_`, `take_`, `skip_`, `takeWhile_`, `skipWhile_`, `ofType_`, `concat_` (after the sync* fix), `union_`, `intersect_`, `except_`, `cast_` all delegate to `iterator` lazily. **Confirmed by deferred-execution tests** in each operator's test file. |
| **Short-circuit** | `any_`, `all_`, `contains_`, `first_`, `firstOrDefault_`, `single_`, `singleOrDefault_`, `elementAt_`, `elementAtOrDefault_` all short-circuit. **Confirmed by `short-circuits on first match` tests** with `Iterable.generate` + `iterCount` counter. |
| **Stable ordering** | `orderBy_` uses Dart's `List.sort`, which is a stable merge sort. **Confirmed by `stable sort: equal ages preserve insertion order` test.** |
| **Resource cleanup** | All `Iterable` wrappers are garbage-collected when the queryable is dropped. The `join_` / `groupJoin_` internal `index` map is built once, not held beyond the iteration. |
| **Null safety** | `MemberAccess.dispatch` and `MethodCall.dispatch` handle `null` targets without NPE. `BinaryExpr` for `==`/`!=` short-circuits before the `num` cast. `where_(predicate)` on a `null` body result is treated as `false`. |
| **String concatenation** | `+` now handles `String + String`, `String + num`, `num + String` correctly via the `'$l$r'` clause. |
| **Cross-operator chaining** | All operators return `IQueryable<T>`, so chaining is type-safe. `where_ → select_ → orderBy_ → take_` works end-to-end. |
| **Generic type preservation** | `select_<TResult>`, `cast_<TResult>`, `groupBy_<TKey>`, `join_<TInner, TKey, TResult>`, `aggregate_<TResult>` all carry the new type through. |
| **Edge case: empty source** | Tested for `where_`, `select_`, `take_`, `skip_`, `orderBy_`, `distinct_`, `concat_`, `union_`, `intersect_`, `except_`, `any_`, `all_`, `contains_`, `count_`, `sum_`, `min_`, `max_`, `first_` (throws), `firstOrDefault_` (null), `single_` (throws), `singleOrDefault_` (null), `groupBy_`, `toList_`, `toSet_`, `toMap_`. |
| **Edge case: single element** | Tested for `single_`, `singleOrDefault_`, `groupBy_`. |
| **Edge case: all duplicates** | Tested for `distinct_`, `union_`, `intersect_`, `except_`. |
| **Edge case: negative count** | `take_(-1)` throws `RangeError`, `skip_(-1)` throws `RangeError` (Dart 3.12+). Documented in the tests. |

---

## 4. What the spike (`examples/spike_sqlite/`) reveals for Fase 2

The spike confirms the SQLite driver works on macOS:

- `package:sqlite3 2.9.4` opens in-memory, executes prepared
  statements, supports `BEGIN` / `COMMIT` / `ROLLBACK`, and survives
  a `'; DROP TABLE …; --` injection attempt.
- 100k inserts in a single transaction take ~70 ms.
- `SELECT … WHERE` with a bind parameter takes ~1.4 ms on 100k rows.

**Implications for the Fase 2 translator:**

- Bind parameters are *positional* (`?` placeholders), not named. The
  translator must emit a flat list of binds in the same order as the
  `?` in the SQL string. We can leverage this for type safety: a
  `where: (u) => u.age > 18` becomes `WHERE age > ?` with
  `binds = [18]`.
- The `package:sqlite3` API is untyped at the row level: `ResultRow`
  is `Map<String, Object?>`. We will need a `Map → RecordLike` mapper
  for translating results back into user types. **L-04 (new):** we
  should add a `SqliteRowReader` helper that reads typed values from
  a row by field name.

---

## 5. Recommendations

1. **Fix B-09 in Fase 2** (before SQL translation starts). It's a
   5-minute change that prevents debugging pain later.
2. **Keep L-01, L-02, L-03 as-is** for Fase 1. They match C# LINQ
   semantics, which is the whole point of the API.
3. **Add a `SqliteRowReader` helper** in the next sprint to support
   type-safe `ResultRow → T` conversion in the Fase 2 SQL provider.
4. **Document L-01..L-03 in the public API** (e.g. in the dartdoc of
   each operator) so users aren't surprised.

---

## 6. Test counts after the review

| Suite | Tests | Status |
|---|---|---|
| `d_rocket/test/linq/*_test.dart` (19 files) | 198 | ✅ all green |
| `examples/spike/test/*_test.dart` (LINQ spike) | 10 | ✅ all green |
| `examples/spike_sqlite/test/*_test.dart` (SQLite spike) | 5 | ✅ all green |
| **Total** | **213** | ✅ |
