# d_rocket 2.6.0 Functional Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the complete 2.6.0 data-layer program: reactive REST queries, value models, advanced forms, serialization/schema contracts, SQLite-focused ORM depth, REST/realtime/sync capabilities, and a published-package compatibility matrix.

**Architecture:** Keep each capability in its owning layer. REST caching and transport contracts stay in the pure Dart runtime; annotations and generated code stay in their builders; forms, serializers and SQLite use independent files and tests; mobile/background/UI integrations remain adapters. Generate value helpers with a sentinel-based `copyWith` extension and an explicit equality mixin because a Dart part cannot reopen a class to add operators.

**Tech Stack:** Dart 3.11.5–3.13, Flutter-compatible pure Dart runtime, `build_runner`, `source_gen`, existing `HttpClient`, `RestClient` and `@Serializable` pipelines, `package:test`.

**Spec:** `docs/superpowers/specs/2026-11-22-d-rocket-2-6-reactive-cache-value-models-design.md`

## Current implementation status

The local 2.6.0 candidate implements the runtime and generated contracts for
REST query caching, value helpers, forms, serialization/converters, SQLite
companions and migration review, typed REST transfers/OpenAPI metadata,
realtime delivery/multiplexing and offline sync checkpoints. The checkboxes
below describe the implementation history; they are not a release claim by
themselves.

The only verification that cannot be completed before publication is resolving
the coordinated versions from pub.dev in a clean external consumer. Native
background scheduling, UI state-management adapters, Socket.IO and CRDTs stay
outside the pure-Dart package by design.

## Global Constraints

- Keep the feature in the Dart/data layer; do not add Flutter, Bloc or Riverpod dependencies.
- Preserve existing behavior when `@QueryCache`, `@Invalidates`, `copyWith` and `equality` are absent.
- Keep one class, enum or explicit language feature per file.
- Use additive APIs and preserve the existing generated-client and serializer contracts.
- Do not evaluate arbitrary tag expressions; support only validated parameter/body-property placeholders.
- Do not inject `operator ==` into a class automatically; require the generated equality mixin when equality is enabled.
- Do not edit generated files manually; regenerate them with build_runner.
- Keep LINQ and ORM scope restricted to SQLite for this program.
- Treat Flutter widgets, Bloc/Riverpod, native schedulers, Socket.IO, CRDTs and
  testcontainers as adapter/extension work, not hidden core dependencies.

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

### Task 6: Advanced forms and error binding

**Files:**
- Create: `packages/d_rocket/lib/src/forms/form_group.dart`
- Create: `packages/d_rocket/lib/src/forms/form_array.dart`
- Create: `packages/d_rocket/lib/src/forms/form_validation_state.dart`
- Modify: `packages/d_rocket/lib/src/forms/validators.dart`
- Modify: `packages/d_rocket_builder/lib/src/forms/*`
- Test: `packages/d_rocket/test/forms/advanced_form_state_test.dart`
- Test: `packages/d_rocket_builder/test/forms/advanced_form_codegen_test.dart`

- [x] **Step 1: Add failing tests** for nested groups, dynamic arrays, reset/default values, dirty/pristine, enabled/disabled, pending and composite bindings.
- [x] **Step 2: Add composable async validators** with debounce, cancellation and `validating`/`valid`/`invalid` state transitions.
- [x] **Step 3: Add cross-field built-ins** such as comparison, matching, membership, containment, `requiredTrue` and credit-card validation without UI widgets.
- [x] **Step 4: Map typed REST/RFC 7807 field errors** to form and field state, preserving server field paths.
- [x] **Step 5: Add builder metadata and generated binding descriptors** for compound fields; reject ambiguous mappings with diagnostics.
- [x] **Step 6: Run focused form tests and commit** with `feat: expand data-layer forms`.

### Task 7: Serialization converters, unknown fields and schemas

**Files:**
- Create: `packages/d_rocket/lib/src/serializer/json_converter.dart`
- Create: `packages/d_rocket/lib/src/serializer/unknown_field_policy.dart`
- Create: `packages/d_rocket/lib/src/serializer/json_schema.dart`
- Modify: `packages/d_rocket/lib/src/serializer/serializable.dart`
- Modify: `packages/d_rocket_builder/lib/src/serializer/*`
- Test: `packages/d_rocket/test/serializer/converter_policy_test.dart`
- Test: `packages/d_rocket_builder/test/serializer/json_schema_codegen_test.dart`

- [ ] **Step 1: Add failing tests** for converter precedence, `readValue`, unknown-field policies, field naming, null inclusion and explicit nested conversion.
- [ ] **Step 2: Cover dates, decimals, enums, UUIDs, nullable nested models, generic envelopes and opaque JSON values** with field-path diagnostics.
- [ ] **Step 3: Implement `JsonConverter<T, Object?>` registration** at global, class and field scope without changing default behavior.
- [ ] **Step 4: Generate JSON Schema and golden fixtures** from the same metadata used by serialization.
- [ ] **Step 5: Run generated-code compilation tests and commit** with `feat: extend serialization contracts`.

### Task 8: SQLite ORM and query tooling

**Files:**
- Create/modify: `packages/d_rocket_engine_sqlite/lib/src/query/*`
- Create/modify: `packages/d_rocket_engine_sqlite/lib/src/sql/*`
- Create/modify: `packages/d_rocket_engine_sqlite/lib/src/migrations/*`
- Test: `packages/d_rocket_engine_sqlite/test/query/*`
- Test: `packages/d_rocket_engine_sqlite/test/migrations/*`

- [ ] **Step 1: Add failing SQLite tests** for manager APIs, incremental predicates, ordering, paging, reactive query granularity and companion-style partial writes.
- [ ] **Step 2: Add extensible SQLite type converters** and validate custom SQL parameters, functions and aggregates.
- [ ] **Step 3: Add SQL/schema inspection and generated migration tests**, explicitly flagging destructive `ALTER TABLE`, drops and type changes for review.
- [ ] **Step 4: Add optional read-isolate/read-pool execution policies** without changing the SQLite public contract.
- [ ] **Step 5: Run the complete SQLite suite and commit** with `feat: deepen sqlite query tooling`.

### Task 9: REST contracts, pagination and transfers

**Files:**
- Create/modify: `packages/d_rocket/lib/src/rest/pagination/*`
- Create/modify: `packages/d_rocket/lib/src/rest/transfer/*`
- Create/modify: `packages/d_rocket/lib/src/rest/openapi/*`
- Modify: `packages/d_rocket_builder/lib/src/rest/*`
- Test: `packages/d_rocket/test/rest/pagination_transfer_test.dart`
- Test: `packages/d_rocket_builder/test/rest/openapi_codegen_test.dart`

- [ ] **Step 1: Add failing tests** for typed pagination, endpoint serializers, multipart upload/download progress and large-body streaming.
- [ ] **Step 2: Add OpenAPI 3.1 export/import** for annotated clients, typed errors and pagination metadata.
- [ ] **Step 3: Integrate auth refresh, retry policy and RFC 7807 mapping** with transport ownership and cancellation preserved.
- [ ] **Step 4: Add contract fixtures and generated-client compilation tests.**
- [ ] **Step 5: Run focused REST tests and commit** with `feat: expand rest contracts and transfers`.

### Task 10: Realtime delivery contracts

**Files:**
- Create/modify: `packages/d_rocket/lib/src/realtime/*`
- Test: `packages/d_rocket/test/realtime/realtime_delivery_test.dart`

- [ ] **Step 1: Add failing tests** for reconnect jitter, heartbeat-aware idle detection, multiplexed channels, backpressure and delivery acknowledgement.
- [ ] **Step 2: Unify observable lifecycle/auth status** for SSE and WebSocket clients, including safe restart and cancellation.
- [ ] **Step 3: Add queued outbound-message policies** with explicit delivery guarantees and bounded memory.
- [ ] **Step 4: Keep Socket.IO and platform negotiation in adapters**; add only extension contracts in core.
- [ ] **Step 5: Run realtime tests and commit** with `feat: strengthen realtime delivery contracts`.

### Task 11: Offline-first synchronization

**Files:**
- Create: `packages/d_rocket/lib/src/sync/delta_sync.dart`
- Create: `packages/d_rocket/lib/src/sync/sync_queue.dart`
- Create: `packages/d_rocket/lib/src/sync/sync_metrics.dart`
- Create: `packages/d_rocket/lib/src/sync/attachment_transfer.dart`
- Test: `packages/d_rocket/test/sync/sync_contract_test.dart`

- [ ] **Step 1: Add failing tests** for delta/incremental sync, partial entity/field sync and conflict-specific retry.
- [ ] **Step 2: Implement a durable queue contract** with resumable attachment transfers and persistent metrics.
- [ ] **Step 3: Expose data-layer conflict inspection/resolution decisions** without adding a UI resolver.
- [ ] **Step 4: Keep native background scheduling in mobile/Flutter adapters** and CRDT support as a separate extension point.
- [ ] **Step 5: Run sync tests and commit** with `feat: add incremental sync contracts`.

### Task 12: Contracts, fixtures and release verification

**Files:**
- Create/modify: `packages/d_rocket/tool/contract_fixtures/*`
- Create/modify: `packages/d_rocket/tool/benchmarks/*`
- Modify: `.github/workflows/compatibility.yml`
- Modify: package READMEs, changelogs and release notes

- [ ] **Step 1: Add REST mocks, fake HTTP servers, migration fixtures, schema/OpenAPI golden tests and generated form metadata fixtures.**
- [ ] **Step 2: Add benchmarks** for REST cache hits/misses, serialization, SQLite CRUD/query chains, sync and realtime delivery.
- [ ] **Step 3: Verify** Dart 3.11.5, 3.12 and 3.13, stable Flutter, and applicable Web/Android/iOS/macOS/Linux targets.
- [ ] **Step 4: Resolve dependencies from published packages in a clean consumer fixture**, in addition to path-based workspace tests.
- [ ] **Step 5: Run `dart analyze`, `dart test`, `dart run build_runner build --delete-conflicting-outputs` and package dry-runs for every affected repository.
- [ ] **Step 6: Review generated diffs, docs and release promises; commit** with `test: verify d_rocket 2.6 compatibility matrix`.

## Final Verification

### Current audit (2026-11-22)

- [x] REST cache, generated annotations, invalidation and logout generation
  safety are implemented and covered by runtime/codegen fixtures.
- [x] Value equality, nullable-safe `copyWith`, converter/read hooks,
  unknown-key policies and generated schemas are implemented and covered.
- [x] Forms cover nested groups/arrays, async validation, dirty/pristine,
  enabled/disabled state, composite callbacks, generated composite metadata,
  reusable validators and RFC 7807 field paths.
- [x] SQLite custom SQL, companions, value converters, serialized reads and
  destructive migration review are implemented and tested.
- [x] REST pagination, transfers, multipart, streaming bodies, progress and
  OpenAPI endpoint metadata are implemented and tested.
- [x] Realtime SSE/WebSocket lifecycle contracts, bounded inbound/outbound
  delivery, acknowledgements and named multiplexed channels are implemented
  and tested.
- [x] Delta sync, durable queue support, resumable attachment state and sync
  metrics are present and covered by sync tests.
- [x] Core and builder analyze cleanly; the SQLite engine analyzes without
  errors and retains ten pre-existing informational notices.
- [x] The CI analyzer gate reports those notices without treating them as
  failures, while still failing on warnings and errors.
- [x] The core package dry-run publishes with zero warnings after removing the
  duplicated DevTools build from its archive.
- [ ] Published-package compatibility resolution remains the release gate;
  it requires the coordinated 2.6.0 packages to exist on pub.dev and is not
  performed during local implementation.

- [ ] `d_rocket` and `d_rocket_builder` analyze cleanly.
- [ ] All existing tests plus new cache/value-model tests pass.
- [ ] Generated files compile from a clean checkout.
- [ ] No Flutter, Bloc or Riverpod dependency was added to core packages.
- [ ] SQLite remains the only ORM/LINQ target in this release program.
- [ ] Adapter candidates (Socket.IO, CRDT, native schedulers, UI conflict screens) are documented without becoming hidden core dependencies.
- [ ] No push or publication occurs until the 2.6.0 release decision is explicit.
