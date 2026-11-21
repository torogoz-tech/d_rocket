# d_rocket 2.5.0 Hardening Design

## Intent

Extend the existing model-driven forms and realtime/REST primitives with the
minimum operational guarantees needed by production Flutter applications:
robust WebSocket lifecycle management, cross-field form validation, and
structured REST failures. The existing `@Uuid` feature remains part of this
release.

## Scope

### WebSocket

`WebSocketReconnector` gains asynchronous headers before every connection,
observable lifecycle states, bounded retry with a counter reset only after a
successful connection, safe stop/restart generation cancellation, optional
401 recovery, explicit HTTP status propagation, and configurable inactivity
detection. Heartbeats continue to be application messages and count as local
activity; incoming messages reset the inactivity timer.

### Forms

Forms gain model-level cross-field validators without one controller per input.
The validator receives the built model after field validators pass, preserving
the existing `FormState<T>` and generated adapter APIs.

### REST

REST failures gain a structured error payload abstraction while preserving
`RestHttpException` compatibility and its existing `problemDetails` access.
Generated clients continue to throw the existing exception type.

## Non-goals

- No DevTools UI changes in this implementation pass.
- No changes to SQLite or ORM behavior.
- No new WebSocket transport implementation for web; the existing connection
  abstraction remains the transport boundary.
- No automatic retry of forbidden WebSocket handshakes.

## Compatibility

This is an additive `2.5.0` release. Existing connection implementations can
use default status behavior, existing forms can omit cross-field validators,
and existing REST consumers can continue to inspect `RestHttpException`.
