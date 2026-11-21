# d_rocket 2.5.0 observability and quality hardening

The second 2.5.0 increment strengthens the existing framework rather than
adding a new layer. Runtime diagnostics must expose useful, redacted events
for realtime transitions; WebSocket connections must preserve failure and
close context; REST errors must expose common structured metadata; and CI must
prove that generated Dart is regenerated and analyzable.

The public API stays compatible with existing `WebSocketConnection`
implementations. Optional transport details are discovered without adding a
new required interface member. Generated files remain build outputs; the
quality gate validates them but never patches them.

## Acceptance

- A WebSocket transition produces a diagnostic event with correlation id,
  state, attempt, status and redacted metadata when diagnostics are enabled.
- WebSocket callers can inspect the last error and optional close code/reason;
  reconnect decisions remain bounded and old events remain suppressed.
- `RestHttpException.problem` exposes RFC 7807 fields, business error code,
  trace/request ids and validation messages while preserving raw JSON.
- CI regenerates d_rocket outputs before analysis and fails on known invalid
  generated constructs.
- Existing APIs, forms, enums, UUID support and all current tests remain
  compatible.
