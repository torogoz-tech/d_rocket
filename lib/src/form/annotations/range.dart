/// Validates that a numeric value is within an inclusive range.
class Range {
  /// Creates an inclusive numeric range validation annotation.
  const Range({
    this.min,
    this.max,
    this.message,
    this.code = 'range.invalid',
  });

  /// Inclusive minimum value.
  final num? min;

  /// Inclusive maximum value.
  final num? max;

  /// Optional message shown when validation fails.
  final String? message;

  /// Stable validation code for localization and telemetry.
  final String code;
}
