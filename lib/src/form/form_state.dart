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
    List<FormValidator<T>>? validators,
    this.validationMode = FormValidationMode.onSubmit,
  })  : _fields = Map<String, FormFieldState<Object?>>.unmodifiable(fields),
        _builder = builder,
        _validators = List<FormValidator<T>>.unmodifiable(
          validators ?? <FormValidator<T>>[],
        ) {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.validationMode = validationMode;
    }
  }

  final Map<String, FormFieldState<Object?>> _fields;
  final T Function() _builder;
  final List<FormValidator<T>> _validators;
  final List<FormError> _formErrors = <FormError>[];

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

    _formErrors.clear();
    if (_buildValidationResult().errors.isNotEmpty) return false;

    final T model = _builder();
    for (final FormValidator<T> validator in _validators) {
      final FormError? error = validator(model);
      if (error != null) _formErrors.add(error);
    }

    return validation.isValid;
  }

  /// Updates multiple fields from one control value.
  ///
  /// The mapper returns raw values keyed by model field name, so each target
  /// field keeps its own parser and validation rules.
  void setCompositeValues(Map<String, Object?> values) {
    for (final MapEntry<String, Object?> entry in values.entries) {
      final FormFieldState<Object?>? field = _fields[entry.key];
      if (field == null) {
        throw ArgumentError.value(entry.key, 'field', 'Unknown form field');
      }
      field.setRawValue(entry.value);
    }
  }

  /// Creates a callback for a control that supplies several model fields.
  void Function(TValue) bindComposite<TValue>(
    Map<String, Object?> Function(TValue value) mapper,
  ) {
    return (TValue value) => setCompositeValues(mapper(value));
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
    _formErrors.clear();
  }

  /// Releases all registered field states.
  Future<void> dispose() async {
    for (final FormFieldState<Object?> field in _fields.values) {
      await field.dispose();
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

    errors.addAll(_formErrors);

    return FormValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
      fieldErrors: fieldErrors,
    );
  }
}
