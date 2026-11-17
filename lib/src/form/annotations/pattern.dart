/// Validates a string value against a regular expression.
class Pattern {
  /// Creates a regular-expression validation annotation.
  const Pattern({
    required this.expression,
    this.message,
    this.code = 'pattern.invalid',
  });

  /// Regular expression source.
  final String expression;

  /// Optional message shown when validation fails.
  final String? message;

  /// Stable validation code for localization and telemetry.
  final String code;
}
