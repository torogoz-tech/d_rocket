# d_rocket 2.5.0

## UUID validation

Form models can replace repeated regular expressions with an explicit
annotation:

```dart
@Required()
@Uuid(version: UuidVersion.v4)
final String requestId;
```

`@Uuid()` accepts canonical UUIDs from versions 1 through 8. The optional
`version` argument restricts the version nibble to a specific
`UuidVersion.v1` through `UuidVersion.v8`. Validation accepts upper- and
lower-case values, requires hyphens, checks the compatible RFC variant and
preserves `message` and `code` for localization and telemetry.

The annotation validates existing values; it does not generate UUIDs. Use
`generateUuidV4()` when a v4 UUID must be created.

## Robust WebSocket reconnecting

`WebSocketReconnector` resolves asynchronous headers before every connection,
publishes `connecting`, `connected`, `retrying`, `stopped` and `failed`, and
can recover a `401` through `onUnauthorized`. A `403` is terminal, the retry
counter resets only after a successful connection, and `inactivityTimeout`
includes heartbeat traffic. `stop()` can be followed by `start()`, while
`dispose()` closes the public streams as well.

## Typed REST errors

`RestHttpException.problem` provides a `RestProblemDetails` view of RFC 7807
payloads, including `validationErrors`, business codes and correlation
metadata. Response `traceId` and `requestId` headers are also available. The
original `problemDetails` access remains available for backend-specific
extensions.

## Diagnostics and code generation

Reconnectors publish correlated `websocket.state` events with state, attempt,
HTTP status and close context. Bodies and validation errors remain hidden
unless sensitive-data capture is explicitly enabled. CI regenerates `.g.dart`
files and runs `dart run tool/verify_generated.dart` before analysis to detect
unexpanded tokens, double nullability, invalid nullable `DateTime` casts and
default lists emitted as `<dynamic>`.

## Cross-field validation

Model-level validators on `FormState<T>` run after field validation and enable
rules such as password confirmation or CVV length based on the detected card
brand. `bindComposite()` keeps controls that feed multiple properties
declarative.

## Asynchronous validation

Generated adapters accept `AsyncFormValidator<T>` and expose
`validateAsync()` and `buildAsync()`. `FormFieldState` and `FormState` publish
`FormValidationState.validating`, `valid` and `invalid`; debounce prevents a
remote request on every keystroke.

```dart
final form = LoginRequestForm(
  asyncValidators: <AsyncFormValidator<LoginRequest>>[
    (LoginRequest? value) => checkEmailAvailability(value?.email),
  ],
  asyncValidationDebounce: const Duration(milliseconds: 300),
);
```

A `RestHttpException` can be applied directly with
`form.applyRestError(error)`, mapping `problem.validationErrors` to generated
fields.

## Serialization diagnostics

Generated conversions now throw `SerializationException` with the model field,
expected type, received value and original cause. The explicit
`UnknownKeyPolicy.strict`, `ignore` and `capture` policies remain available;
dates, decimal equivalents (`double`/`num`), enums and UUIDs continue to use
their existing declarative contracts.

## Compatibility

The compatibility workflow regenerates and tests the package with Dart 3.11.5,
3.12.0 and 3.13.0 together with stable Flutter. The optional verification
mode resolves dependencies exclusively from pub.dev for the published package
line.
