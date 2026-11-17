/// A stable validation failure associated with a form field.
class FormError {
  /// Creates an immutable form error.
  const FormError({
    required this.code,
    required this.message,
  });

  /// Stable machine-readable code.
  final String code;

  /// Human-readable message for the current locale.
  final String message;
}
