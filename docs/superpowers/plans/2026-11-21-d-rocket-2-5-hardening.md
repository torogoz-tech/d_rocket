# d_rocket 2.5.0 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden d_rocket realtime and form/REST integration for the 2.5.0 release while preserving existing APIs.

**Architecture:** Extend `WebSocketConnection` with optional status information and add a state enum beside `WebSocketReconnector`; keep reconnection policy and generation cancellation inside the reconnector. Add cross-field validators to `FormState<T>` and let generated forms forward model-level validators. Preserve `RestHttpException` and add structured payload access through a focused REST error type/helper.

**Tech Stack:** Dart 3.11+, `d_rocket`, `d_rocket_builder`, `package:test`, `build_runner`.

**Spec:** `docs/superpowers/specs/2026-11-21-d-rocket-2-5-hardening-design.md`

## Global Constraints

- Target release remains `d_rocket 2.5.0` and `d_rocket_builder 2.5.0`.
- Do not alter SQLite/ORM or DevTools in this plan.
- Preserve existing WebSocket, SSE, REST, form, and validator behavior.
- Keep one public class or enum per file.
- No push or publish without explicit authorization.

## Review Focus

- A stopped or restarted WebSocket cannot emit messages from an older connection.
- A failed WebSocket handshake does not reset the retry budget before success.
- A successful connection resets the retry budget before the next disconnect.
- `401` recovery refreshes headers once per failed handshake; `403` is terminal.
- Cross-field errors run only after field errors pass and do not construct an invalid model.

### Task 1: Harden WebSocket reconnection

**Files:**
- Create: `lib/src/realtime/websocket_reconnector_state.dart`
- Modify: `lib/src/realtime/websocket_connection.dart`
- Modify: `lib/src/realtime/websocket_reconnector.dart`
- Modify: `lib/src/realtime/websocket.dart`
- Test: `test/realtime/websocket_reconnector_test.dart`

- [ ] Add failing tests for dynamic headers, lifecycle states, bounded failed handshakes, restart cancellation, 401 recovery, 403 terminal behavior, and inactivity timeout.
- [ ] Implement the smallest stateful reconnector change that passes the tests while keeping `factory` and `messages` compatible.
- [ ] Run focused realtime tests and the full d_rocket test suite.
- [ ] Commit the WebSocket hardening.

### Task 2: Add model-level cross-field form validation

**Files:**
- Create or modify: `lib/src/form/form_validator.dart` or existing form state contract.
- Modify: `lib/src/form/form_state.dart`.
- Modify: `lib/src/form/form_annotations.dart` only if annotation metadata is needed.
- Modify: builder form metadata/writer if generated adapters need a model validator hook.
- Test: `test/form/form_state_test.dart` and generated form coverage.

- [ ] Add a failing test for a cross-field rule such as confirmation matching password.
- [ ] Ensure field-level errors prevent model construction and cross-field validators run afterward.
- [ ] Implement the model-level validator list without introducing per-input controllers.
- [ ] Run form and codegen tests.
- [ ] Commit the form validation change.

### Task 3: Structure REST error payloads

**Files:**
- Modify: `lib/src/rest/error.dart` or create a focused error payload file.
- Modify: `lib/src/rest/rest.dart`.
- Test: `test/rest/error_test.dart`.

- [ ] Add failing tests for problem-details fields, arbitrary validation details, and compatibility with `RestHttpException`.
- [ ] Implement structured access without changing exception types thrown by generated clients.
- [ ] Run REST tests and the full suite.
- [ ] Commit the REST error improvement.

### Task 4: Release documentation and verification

**Files:**
- Modify: `CHANGELOG.md` and release guide in each affected package.
- Modify: `README.md` where the 2.5.0 feature surface is listed.
- Test: generated fixtures and CI-equivalent commands.

- [ ] Document WebSocket lifecycle, cross-field validation, REST errors, and `@Uuid`.
- [ ] Run `dart analyze`, `dart test`, and `dart run build_runner build --delete-conflicting-outputs`.
- [ ] Run package publish dry-runs only.
- [ ] Review all diffs and leave changes committed locally without push or publish.
