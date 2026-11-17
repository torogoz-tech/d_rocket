/// Requires a value that is not null, empty or whitespace-only.
class Required {
  /// Creates a required-value validation annotation.
  const Required({
    this.message,
    this.code = 'required',
  });

  /// Optional message shown when validation fails.
  final String? message;

  /// Stable validation code for localization and telemetry.
  final String code;
}
