# d_rocket 2.6.0 Reactive Cache and Value Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a framework-independent reactive REST query cache with tag invalidation and opt-in generated `copyWith`/value equality helpers for 2.6.0.

**Architecture:** Keep query caching in the d_rocket REST runtime as an instance-scoped `RestQueryCache`, then let the REST builder translate annotations into cache and invalidation calls. Keep value helpers in serializer codegen: generate a sentinel-based extension for `copyWith` and an explicit generated equality mixin because a Dart part cannot reopen a class to add operators.

**Tech Stack:** Dart 3.11.5–3.13, Flutter-compatible pure Dart runtime, `build_runner`, `source_gen`, existing `HttpClient`, `RestClient` and `@Serializable` pipelines, `package:test`.

**Spec:** `docs/superpowers/specs/2026-11-22-d-rocket-2-6-reactive-cache-value-models-design.md`

## Global Constraints

- Keep the feature in the Dart/data layer; do not add Flutter, Bloc or Riverpod dependencies.
- Preserve existing behavior when `@QueryCache`, `@Invalidates`, `copyWith` and `equality` are absent.
- Keep one class, enum or explicit language feature per file.
- Use additive APIs and preserve the existing generated-client and serializer contracts.
- Do not evaluate arbitrary tag expressions; support only validated parameter/body-property placeholders.
- Do not inject `operator ==` into a class automatically; require the generated equality mixin when equality is enabled.
- Do not edit generated files manually; regenerate them with build_runner.

## Review Focus

- Two subscribers to one query must produce one HTTP request and receive the same refreshed value.
- A failed mutation must not invalidate cached financial data, while a successful mutation must refetch active matching queries.
- `clearQueryCache()` must prevent a late in-flight response from repopulating data after logout.
- `copyWith` must distinguish an omitted nullable argument from an explicit `null`.
- Equality must be deterministic for nested lists, sets, maps and nullable fields without coupling to a state-management package.

### Task 1: REST cache runtime contract

**Files:**
- Create: `packages/d_rocket/lib/src/rest/query_cache_entry.dart`
- Create: `packages/d_rocket/lib/src/rest/query_cache_subscription.dart`
- Create: `packages/d_rocket/lib/src/rest/rest_query_cache.dart`
- Create: `packages/d_rocket/lib/src/rest/rest_query_cache_options.dart`
- Modify: `packages/d_rocket/lib/src/rest/rest.dart`
- Modify: `packages/d_rocket/lib/src/rest/client/rest_client.dart`
- Test: `packages/d_rocket/test/rest/rest_query_cache_test.dart`

**Interfaces:**
- Produce `RestQueryCache.watch<T>({required String key, required Iterable<String> tags, required Future<T> Function() loader, Duration? staleTime, Duration? cacheTime}) -> Stream<T>`.
- Produce `RestQueryCache.invalidate(Iterable<String> tags) -> Future<void>`.
- Produce `RestQueryCache.clear() -> Future<void>`.
- Expose the cache through `DRest.queryCache` and `DRest.clearQueryCache()`.

- [ ] **Step 1: Write failing runtime tests** for concurrent deduplication, stale reuse, active invalidation/refetch, cache eviction, errors and generation-safe clear.
- [ ] **Step 2: Run the focused tests** and verify they fail because the runtime contract does not exist.
- [ ] **Step 3: Implement the cache** with normalized key records, in-flight futures, reference-counted broadcast streams, tag indexes, stale/cache timers and a generation counter.
- [ ] **Step 4: Add the DRest facade** without changing existing `HttpCache` behavior.
- [ ] **Step 5: Run `dart test test/rest/rest_query_cache_test.dart`** and verify all cases pass.
- [ ] **Step 6: Commit** with `feat: add reactive rest query cache`.

### Task 2: REST cache annotations and generated clients

**Files:**
- Create: `packages/d_rocket/lib/src/rest/annotations/query_cache.dart`
- Create: `packages/d_rocket/lib/src/rest/annotations/invalidates.dart`
- Modify: `packages/d_rocket/lib/src/rest/annotations/annotations.dart`
- Modify: `packages/d_rocket/lib/d_rocket.dart`
- Create: `packages/d_rocket_builder/lib/src/rest/query_cache_metadata.dart`
- Modify: `packages/d_rocket_builder/lib/src/rest/parser.dart`
- Modify: `packages/d_rocket_builder/lib/src/rest/emitter.dart`
- Test: `packages/d_rocket_builder/test/rest_query_cache_codegen_test.dart`
- Test: `packages/d_rocket/test/rest/generated_query_cache_test.dart`

**Interfaces:**
- `QueryCache({required List<String> tags, Duration staleTime, Duration cacheTime})`.
- `Invalidates({required List<String> tags})`.
- Extend parsed REST methods with cache metadata and invalidation templates.
- Generated query methods call `dRest.queryCache.watch` and generated mutations call `invalidate` only after a successful response.

- [ ] **Step 1: Add failing generator fixtures** for path placeholders, body-property placeholders, static tags, non-cached methods and failed mutations.
- [ ] **Step 2: Run builder tests** and verify annotations are not recognized/generated yet.
- [ ] **Step 3: Implement annotation metadata parsing** with validation for supported placeholders and `Stream<T>` query return types.
- [ ] **Step 4: Emit normalized keys and tag resolvers** from actual method parameters; reject unsupported expressions with `InvalidGenerationSourceError`.
- [ ] **Step 5: Emit post-success invalidation** while preserving return values, errors, cancellation and existing per-instance base URL behavior.
- [ ] **Step 6: Regenerate fixtures and run builder/core focused tests.**
- [ ] **Step 7: Commit** with `feat: generate reactive rest cache contracts`.

### Task 3: Serializable options and equality runtime helper

**Files:**
- Create: `packages/d_rocket/lib/src/serializer/value_equality.dart`
- Modify: `packages/d_rocket/lib/src/serializer/serializable.dart`
- Modify: `packages/d_rocket/lib/src/serializer/serializer.dart`
- Modify: `packages/d_rocket/lib/d_rocket.dart`
- Test: `packages/d_rocket/test/serializer/value_equality_test.dart`

**Interfaces:**
- Add `Serializable.copyWith` and `Serializable.equality`, both defaulting to `false`.
- Produce `ValueEquality.equals(Object? left, Object? right) -> bool` and `ValueEquality.hash(Object? value) -> int` for nested JSON-like values.

- [ ] **Step 1: Write failing tests** for scalar, nullable, nested list/map/set equality and stable hash results.
- [ ] **Step 2: Run focused serializer tests** and verify the new API is absent.
- [ ] **Step 3: Implement the dependency-free deep equality helper** with cycle-safe behavior for supported JSON-like values and deterministic map key ordering.
- [ ] **Step 4: Add additive annotation flags and public exports.**
- [ ] **Step 5: Run `dart test test/serializer/value_equality_test.dart`** and verify all cases pass.
- [ ] **Step 6: Commit** with `feat: add generated value equality support`.

### Task 4: Serializer codegen for copyWith and equality

**Files:**
- Create: `packages/d_rocket_builder/lib/src/serializer/value_model_writer.dart`
- Modify: `packages/d_rocket_builder/lib/src/serializer/generator.dart`
- Test: `packages/d_rocket_builder/test/serializer/value_model_codegen_test.dart`
- Test: `packages/d_rocket/test/serializer/generated_value_model_test.dart`

**Interfaces:**
- When `copyWith: true`, generate `<ModelName>CopyWith` with a typed `copyWith({ ... })` method and a private sentinel for explicit nullable nulls.
- When `equality: true`, generate `mixin _$<ModelName>Equality on <ModelName>` implementing `operator ==` and `hashCode` using `ValueEquality`.
- Emit a clear generation error when equality is enabled without `with _$<ModelName>Equality` on the model.

- [ ] **Step 1: Add failing fixtures/tests** for required fields, nullable fields set to null, omitted fields, nested values and equality mixin validation.
- [ ] **Step 2: Run builder tests** and verify generated helpers are missing or invalid.
- [ ] **Step 3: Implement constructor metadata analysis** and reject unsupported constructors with actionable diagnostics.
- [ ] **Step 4: Generate the copyWith extension and equality mixin** in a dedicated writer, preserving generic and nullable types.
- [ ] **Step 5: Regenerate fixtures and run builder/core focused tests.**
- [ ] **Step 6: Commit** with `feat: generate copyWith and equality helpers`.

### Task 5: Integration, docs and compatibility

**Files:**
- Modify: `packages/d_rocket/README.md`
- Modify: `packages/d_rocket/CHANGELOG.md`
- Create: `packages/d_rocket/doc/RELEASE_2.6.0.md`
- Modify: `packages/d_rocket_builder/README.md`
- Modify: `packages/d_rocket_builder/CHANGELOG.md`
- Create: `packages/d_rocket_builder/doc/RELEASE_2.6.0.md`
- Modify: `packages/d_rocket/doc/STATUS.md`
- Modify: `packages/d_rocket/doc/ROADMAP.md`
- Modify: `.github/workflows/compatibility.yml`

- [ ] **Step 1: Add end-to-end tests** covering a cached GET, successful mutation invalidation, logout clearing and a generated model with both options.
- [ ] **Step 2: Document cache lifecycle, tag syntax, security rules, constructor constraints and equality-mixin usage.**
- [ ] **Step 3: Extend compatibility checks** for generated cache contracts and value helpers across Dart 3.11.5, 3.12 and 3.13; run published-package resolution after publication.
- [ ] **Step 4: Run `dart analyze`, `dart test`, `dart run build_runner build --delete-conflicting-outputs` and `dart run tool/verify_generated.dart` in both repositories.
- [ ] **Step 5: Review generated diffs and package dry-runs.**
- [ ] **Step 6: Commit documentation and integration tests** with `docs: prepare d_rocket 2.6.0 plan and contracts`.

## Final Verification

- [ ] `d_rocket` and `d_rocket_builder` analyze cleanly.
- [ ] All existing tests plus new cache/value-model tests pass.
- [ ] Generated files compile from a clean checkout.
- [ ] No Flutter, Bloc or Riverpod dependency was added.
- [ ] No push or publication occurs until the 2.6.0 release decision is explicit.
