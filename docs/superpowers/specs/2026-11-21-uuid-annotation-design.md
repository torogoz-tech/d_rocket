# UUID Validation Annotation Design

## Intent

Reduce repeated UUID regular expressions in model declarations while keeping
validation model-driven and usable by the generated form layer. The feature
belongs to `d_rocket` annotations and `d_rocket_builder` validation metadata;
it does not depend on REST, ORM, SQLite, or realtime transports.

## Contract

```dart
@Uuid()
final String requestId;

@Uuid(version: UuidVersion.v4)
final String publicId;
```

`@Uuid()` accepts canonical, hyphenated UUID values with hexadecimal digits,
variant bits from the RFC-compatible variant, and any supported version from
1 through 8. `version:` restricts the version nibble to the selected
`UuidVersion` value. The annotation is case-insensitive and validates the
string shape; UUID generation remains separate from validation.

The public API includes `UuidVersion.v1` through `UuidVersion.v8`, plus the
optional `message` and stable `code` fields used by the existing validation
annotations. Version 2 is accepted as a format/version policy even though it
is uncommon; the validator does not generate UUIDs.

## Goals

- Replace repeated UUID `@Pattern` expressions with a named annotation.
- Preserve the existing model-driven validation pipeline and error metadata.
- Support general UUID validation and explicit version validation.
- Keep the annotation usable on nullable fields without duplicating nullability
  checks already handled by the form runtime.
- Document the API for the 2.5.0 release.

## Non-goals

- Generating UUID values from the annotation.
- Replacing `generateUuidV4()`.
- Changing serializer, ORM, REST, SSE, or WebSocket behavior.
- Accepting braces, urns, or non-hyphenated UUID spellings in the first version.

## Validation rules

- The value must be a canonical `8-4-4-4-12` hexadecimal UUID string.
- The variant nibble must be `8`, `9`, `a`, `b`, `A`, or `B`.
- `@Uuid()` accepts version nibbles `1` through `8`.
- `@Uuid(version: UuidVersion.vN)` accepts only nibble `N`.
- A `null` value is left to `@Required` and the existing nullable-field policy.
- Empty and malformed values produce the annotation's `message` and `code`.

## Compatibility

This is an additive 2.5.0 feature. Existing `@Pattern` declarations remain
valid and unchanged. No package other than `d_rocket` and
`d_rocket_builder` needs a version change for this annotation.
