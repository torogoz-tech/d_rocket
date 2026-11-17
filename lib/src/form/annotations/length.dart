/// Validates the length of a string value.
class Length {
  /// Creates a string length validation annotation.
  const Length({
    this.min,
    this.max,
    this.message,
    this.code = 'length.invalid',
  });

  /// Inclusive minimum length.
  final int? min;

  /// Inclusive maximum length.
  final int? max;

  /// Optional message shown when validation fails.
  final String? message;

  /// Stable validation code for localization and telemetry.
  final String code;
}
