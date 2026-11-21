# UUID Annotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a model-driven `@Uuid` validator with optional UUID version restrictions for the d_rocket 2.5.0 form/codegen pipeline.

**Architecture:** Keep the public annotation and `UuidVersion` enum in separate d_rocket files, export them through the existing form annotation barrel, and teach the builder's form metadata/source writer to emit the same runtime validation contract used by `@Pattern`. UUID generation remains independent.

**Tech Stack:** Dart 3.11+, `package:test`, `d_rocket`, `d_rocket_builder`, source generation, model-driven form validation.

**Spec:** `docs/superpowers/specs/2026-11-21-uuid-annotation-design.md`

## Global Constraints

- Target release: `d_rocket 2.5.0` and `d_rocket_builder 2.5.0`.
- Preserve existing `@Pattern`, `@Required`, `@Email`, `@Length`, and `@Range` behavior.
- Support UUID versions 1 through 8; `@Uuid()` accepts any supported version.
- Validate canonical hyphenated UUIDs only in this release.
- Do not change REST, ORM, SQLite, SSE, or WebSocket behavior.
- Keep one public class or enum per file.

## Review Focus

- A valid UUID v4 passes general and explicit-v4 validation.
- A valid UUID from another supported version passes `@Uuid()` but fails a mismatched explicit version.
- Invalid hexadecimal, shape, variant, and version nibbles fail with the configured error metadata.
- Nullable values do not become invalid solely because they are `null`.
- Existing pattern and other annotation validators remain unchanged.

### Task 1: Add the public UUID annotation API in d_rocket

**Files:**
- Create: `lib/src/form/annotations/uuid_version.dart`
- Create: `lib/src/form/annotations/uuid.dart`
- Modify: `lib/src/form/form_annotations.dart`
- Test: `test/form/annotation_contract_test.dart`

**Interfaces:**
- Produces `enum UuidVersion { v1, v2, v3, v4, v5, v6, v7, v8 }`.
- Produces `const Uuid({UuidVersion? version, String? message, String code = 'uuid.invalid'})`.

- [ ] Write tests for default metadata, each enum value, custom message/code, and nullable annotation usage.
- [ ] Run the focused d_rocket annotation tests and verify the new tests fail before implementation.
- [ ] Implement the enum and annotation with Dartdoc and export both from the form annotation barrel.
- [ ] Run focused tests and `dart analyze`.
- [ ] Commit the d_rocket annotation API independently.

### Task 2: Add builder-side UUID validation generation

**Files:**
- Modify: `lib/src/form/form_metadata.dart`
- Modify: `lib/src/form/form_source_writer.dart`
- Test: `test/form/annotation_contract_test.dart` or the existing generated-form tests in the builder package.

**Interfaces:**
- Consumes `Uuid` metadata from the resolved annotation element.
- Produces generated validation equivalent to the UUID rules in the design spec, with configured message and code.

- [ ] Add failing generated-form tests for general UUIDs, v-specific UUIDs, malformed values, and nullable values.
- [ ] Run the focused builder tests and verify the failures are caused by missing UUID support.
- [ ] Implement metadata extraction and generated validation without changing the existing `Pattern` path.
- [ ] Run focused tests, `dart analyze`, and generation for a fixture model.
- [ ] Commit the builder implementation independently.

### Task 3: Document and verify the 2.5.0 release surface

**Files:**
- Modify: `CHANGELOG.md` in `d_rocket`.
- Modify: `README.md` or the form documentation in `d_rocket`.
- Modify: `CHANGELOG.md` in `d_rocket_builder`.
- Create: release guide for 2.5.0 in both packages if the repositories use separate guides.

- [ ] Document `@Uuid()` and `@Uuid(version: UuidVersion.v4)` with valid examples.
- [ ] Run the full `dart analyze` and `dart test` suites in both repositories.
- [ ] Run `dart run build_runner build --delete-conflicting-outputs` against the fixture project.
- [ ] Verify generated code compiles and existing UUID generation tests remain green.
- [ ] Review package versions and prepare, but do not publish or push unless explicitly requested.
