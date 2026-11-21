# d_rocket 2.5.0 Observability and Quality Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add production-grade diagnostics, WebSocket failure context, structured REST metadata, and generated-code quality gates to the 2.5.0 release.

**Architecture:** Extend the existing diagnostics hub and decorators without introducing a required transport interface member. Keep structured REST data in a focused value object. Make codegen verification a regeneration/analyze gate plus source-level regression tests.

**Tech Stack:** Dart 3.11+, `dart:io`, `package:test`, `build_runner`, `analyzer`, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-21-d-rocket-2-5-observability-quality-design.md`

## Global Constraints

- No push or publish.
- Preserve public implementations of `WebSocketConnection`.
- Never edit generated `.g.dart` files manually.
- Keep one class/enum/explicit language feature per file.
- Run `dart analyze`, `dart test`, and `dart run build_runner build --delete-conflicting-outputs`.

## Review Focus

- A reconnecting WebSocket must not leak a stale event after stop/restart.
- A transport that does not expose optional status or close fields must still work.
- Problem payloads with non-string extension values must not crash typed parsing.
- Redacted diagnostics must not include authorization or body secrets.
- Regeneration must detect invalid generated tokens, not merely finish successfully.

### Task 1: Realtime diagnostics and close context

**Files:**
- Modify `lib/src/realtime/websocket_reconnector.dart`, `lib/src/realtime/diagnostic_websocket_connection.dart`, `lib/src/realtime/io_websocket_client.dart`.
- Test `test/realtime/websocket_reconnector_reconnect_test.dart`, `test/diagnostics/realtime_diagnostics_test.dart`.

- [ ] Add failing tests for state events with correlation id, last error, and close metadata.
- [ ] Run targeted tests and confirm failure before implementation.
- [ ] Implement optional close-detail extraction, reconnect failure context, and `websocket.state` diagnostics using existing redaction policy.
- [ ] Run targeted realtime and diagnostics tests.

### Task 2: Structured REST metadata

**Files:**
- Modify `lib/src/rest/rest_problem_details.dart`, `lib/src/rest/error.dart`, `lib/src/rest/client/http_package_client.dart`.
- Test `test/rest/rest_problem_details_test.dart`, `test/diagnostics/rest_diagnostics_test.dart`.

- [ ] Add failing tests for business code, trace id, request id, and response headers.
- [ ] Run targeted tests and confirm failure.
- [ ] Implement normalized typed access while preserving `problemDetails` and raw body behavior.
- [ ] Run REST and diagnostics tests.

### Task 3: Codegen quality gates

**Files:**
- Modify `.github/workflows/ci.yml`.
- Create `test/codegen/generated_output_sanity_test.dart`.
- Add regression assertions to `packages/d_rocket_builder/test/serializer/contract_registry_test.dart` and related emitter tests as needed.

- [ ] Add failing source sanity assertions for invalid generated tokens and generic aliases.
- [ ] Run the test to prove the gate catches a deliberately invalid fixture in memory.
- [ ] Implement the reusable scan and CI regeneration/analyze step; do not mutate generated files.
- [ ] Run d_rocket and builder codegen tests.

### Task 4: Documentation and release verification

**Files:**
- Modify `CHANGELOG.md`, `README.md`, `doc/05-layer-2-rest.md`, `doc/09-layer-6-realtime.md`, `doc/RELEASE_2.5.0.md`.
- Modify the SDD ledger under `.superpowers/sdd/`.

- [ ] Document public APIs, redaction rules, close context and CI gate.
- [ ] Run full analyze, tests, build_runner and pub dry-run.
- [ ] Review the diff, commit locally, and verify no push/publish occurred.
