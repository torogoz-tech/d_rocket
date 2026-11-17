import 'form_error.dart';
import 'form_field_state.dart';
import 'form_validation_mode.dart';
import 'form_validation_result.dart';

/// Coordinates generated field states and safely constructs a model.
class FormState<T> {
  /// Creates a form state around registered fields and a model constructor.
  FormState({
    required Map<String, FormFieldState<Object?>> fields,
    required T Function() builder,
    this.validationMode = FormValidationMode.onSubmit,
  })  : _fields = Map<String, FormFieldState<Object?>>.unmodifiable(fields),
        _builder = builder {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.validationMode = validationMode;
    }
  }

  final Map<String, FormFieldState<Object?>> _fields;
  final T Function() _builder;

  /// Controls automatic validation for registered fields.
  final FormValidationMode validationMode;

  /// Registered generated fields by model field name.
  Map<String, FormFieldState<Object?>> get fields => _fields;

  /// Current validation result without triggering another validation pass.
  FormValidationResult get validation => _buildValidationResult();

  /// Whether all fields are currently valid.
  bool get isValid => validation.isValid;

  /// All current field errors.
  List<FormError> get errors => validation.errors;

  /// Validates every registered field.
  bool validate() {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.validate();
    }

    return validation.isValid;
  }

  /// Builds the model only after a successful validation.
  T build() {
    if (!validate()) {
      throw StateError('Cannot build an invalid form');
    }

    return _builder();
  }

  /// Marks every registered field as touched.
  void touchAll() {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.touch();
    }
  }

  /// Restores every registered field to its initial state.
  void reset() {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.reset();
    }
  }

  FormValidationResult _buildValidationResult() {
    final List<FormError> errors = <FormError>[];
    final Map<String, List<FormError>> fieldErrors =
        <String, List<FormError>>{};

    for (final MapEntry<String, FormFieldState<Object?>> entry
        in _fields.entries) {
      final List<FormError> currentErrors = entry.value.errors;
      if (currentErrors.isEmpty) {
        continue;
      }

      fieldErrors[entry.key] = currentErrors;
      errors.addAll(currentErrors);
    }

    return FormValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      fieldErrors: fieldErrors,
    );
  }
}
