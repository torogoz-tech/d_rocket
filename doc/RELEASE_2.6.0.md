# d_rocket 2.6.0 — implementation status

This document tracks the 2.6.0 functional-parity program before the package
version is bumped or published.

## Implemented in the current worktree

- Reactive REST query cache with deduplication, tag invalidation and safe
  logout clearing.
- Generated REST contracts for `@QueryCache` and `@Invalidates`.
- Opt-in generated `copyWith`, deep equality and JSON Schema metadata.
- Explicit serializer converters and `@JsonKey(readValue: ...)`.
- Nested/dynamic form groups and arrays.
- Typed REST pagination/transfer contracts and field-level sync deltas.
- Validated custom SQLite query contracts.
- End-to-end generated REST cache fixture covering request deduplication and
  successful tag invalidation.
- Generated `@JsonKey(readValue: ...)` fixture and runtime verification.
- Bounded realtime delivery queue with explicit acknowledgements.
- Resumable attachment chunks and progress checkpoints for sync adapters.

## Still required before release

OpenAPI import/export, complete pagination codegen, global/class converter
metadata, SQLite companion/read-pool APIs and the published-package
compatibility matrix remain pending. The realtime and attachment work currently
provides pure-Dart contracts; transport/storage adapters still need to be
implemented. The authoritative task list is the
[2.6.0 implementation plan](../docs/superpowers/plans/2026-11-22-d-rocket-2-6-reactive-cache-value-models.md).

No generated file is edited manually. Generated fixtures are recreated with
`dart run build_runner build --delete-conflicting-outputs`.
