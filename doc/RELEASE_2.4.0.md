# d_rocket 2.4.0

This release groups the transport, diagnostics, realtime ownership and form
integration improvements needed by applications that combine REST, SSE and
Flutter controls.

## Transport and retry policy

`TransportPolicy` can be supplied to `RestClientConfig` and `HttpSseClient`.
It receives the concrete request context for each attempt, can provide dynamic
headers, and can request a bounded repeat after a response. `RetryRequestContext`
adds method, URI, status, attempt and idempotency information to REST retry
decisions. A `CancelToken` interrupts retry backoff instead of waiting for the
full delay.

## SSE transport ownership

An injected `http.Client` is shared by default:

```dart
final client = HttpSseClient(httpClient: sharedClient);
```

If the SSE client owns the injected transport, declare it explicitly:

```dart
final client = HttpSseClient(
  httpClient: transport,
  ownsHttpClient: true,
);
```

`close()` is idempotent, cancels the response stream and closes the transport
only when ownership is enabled.

## Forms and Flutter

`FormFieldState.changes` emits parsed and raw values after `setValue`,
`setRawValue` and `reset`. `FormState.dispose()` releases the registered field
streams. The separate `d_rocket_flutter` package exposes
`DrocketFormBuilder` and `FormBindingField`; applications continue using their
own `TextField`, dropdown, date picker or custom control. For text controls,
`FormBinding.text(name, controller)` synchronizes model normalization and reset
with the caller-owned `TextEditingController`; disposing the binding does not
dispose that controller.

```dart
DrocketFormBuilder<Login>(
  form: loginForm,
  builder: (context, binding) {
    final email = binding.field('email');
    return TextField(
      onChanged: email.onChangedRaw,
      decoration: InputDecoration(errorText: email.errorText),
    );
  },
)
```
