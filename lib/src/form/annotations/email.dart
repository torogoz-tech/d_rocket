/// Requires a string value to use a valid email shape.
class Email {
  /// Creates an email validation annotation.
  const Email({
    this.message,
    this.code = 'email.invalid',
  });

  /// Optional message shown when validation fails.
  final String? message;

  /// Stable validation code for localization and telemetry.
  final String code;
}
