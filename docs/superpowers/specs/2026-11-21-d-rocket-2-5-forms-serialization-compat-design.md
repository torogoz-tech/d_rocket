# d_rocket 2.5.0 forms, serialization and compatibility

This increment extends the existing model-driven form and serializer layers.
Async validators are additive and preserve `validate()`/`build()` behavior.
Generated forms forward the new async and REST-error APIs. Generated field
conversions gain structured diagnostics without changing successful wire
formats. Compatibility is verified through a Dart SDK matrix with Flutter
stable and a manual pub.dev-only dependency graph check.

Acceptance: async validation is debounced and race-safe; validation states are
observable; REST field errors map to existing field state; unknown-key policy,
dates, decimal-equivalent numbers, enums and UUIDs remain explicit; conversion
failures identify their model field; CI regenerates and tests Dart 3.11.5,
3.12.0 and 3.13.0.
