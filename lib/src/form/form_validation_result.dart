import 'form_error.dart';

/// Immutable result of validating a form and its fields.
class FormValidationResult {
  /// Creates a validation result with field-associated errors.
  FormValidationResult({
    required this.isValid,
    required List<FormError> errors,
    required Map<String, List<FormError>> fieldErrors,
  })  : errors = List<FormError>.unmodifiable(errors),
        fieldErrors = Map<String, List<FormError>>.unmodifiable(
          fieldErrors.map(
            (String name, List<FormError> values) => MapEntry(
              name,
              List<FormError>.unmodifiable(values),
            ),
          ),
        );

  /// Whether every registered field is valid.
  final bool isValid;

  /// All field errors in field registration order.
  final List<FormError> errors;

  /// Errors grouped by generated field name.
  final Map<String, List<FormError>> fieldErrors;
}
