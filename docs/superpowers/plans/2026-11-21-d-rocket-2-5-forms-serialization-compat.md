# d_rocket 2.5.0 Forms, Serialization and Compatibility Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add async forms, structured serializer failures and reproducible SDK/package compatibility checks to 2.5.0.

**Architecture:** Add async APIs beside existing synchronous APIs. Keep REST integration in `FormState` and generated forwarding methods. Wrap generated field decoding through one runtime serializer helper. Use CI workflows for SDK and pub.dev graph verification.

**Tech Stack:** Dart, Flutter stable, build_runner, analyzer and package:test.

**Spec:** `docs/superpowers/specs/2026-11-21-d-rocket-2-5-forms-serialization-compat-design.md`

## Global Constraints

- No push or publish.
- Preserve `validate()` and `build()` behavior.
- Do not edit generated `.g.dart` files manually.
- Keep compatibility with existing `WebSocketConnection`, enum, UUID and decimal policies.

### Task 1: Async forms and REST errors

- [x] Add red tests for debounce, observable states, REST error mapping and generated forwarding.
- [x] Implement `AsyncFormValidator`, `FormValidationState`, async field/form validation, `buildAsync()` and `applyRestError()`.
- [x] Update builder output and regenerate fixtures.

### Task 2: Serialization diagnostics

- [x] Add a red test for field-aware conversion failures.
- [x] Implement `SerializationException` and generated decode wrapping.
- [x] Preserve unknown-key, date, decimal-equivalent, enum and UUID contracts.

### Task 3: Compatibility verification

- [x] Add Dart SDK matrix, Flutter stable setup and manual pub.dev-only graph workflow.
- [x] Update release documentation and changelogs.
- [ ] Run full final verification and commit locally.
