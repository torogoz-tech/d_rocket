import 'dart:async';

import 'form_error.dart';
import 'form_field_state.dart';
import 'form_validation_mode.dart';
import 'form_validation_state.dart';
import 'form_validation_result.dart';
import 'form_validator.dart';
import '../rest/error.dart';
import '../rest/rest_problem_details.dart';

/// Coordinates generated field states and safely constructs a model.
class FormState<T> {
  /// Creates a form state around registered fields and a model constructor.
  FormState({
    required Map<String, FormFieldState<Object?>> fields,
    required T Function() builder,
    List<FormValidator<T>>? validators,
    List<AsyncFormValidator<T>>? asyncValidators,
    this.asyncValidationDebounce,
    this.validationMode = FormValidationMode.onSubmit,
  })  : _fields = Map<String, FormFieldState<Object?>>.unmodifiable(fields),
        _builder = builder,
        _validators = List<FormValidator<T>>.unmodifiable(
          validators ?? <FormValidator<T>>[],
        ),
        _asyncValidators = List<AsyncFormValidator<T>>.unmodifiable(
          asyncValidators ?? <AsyncFormValidator<T>>[],
        ) {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.validationMode = validationMode;
    }
  }

  final Map<String, FormFieldState<Object?>> _fields;
  final T Function() _builder;
  final List<FormValidator<T>> _validators;
  final List<AsyncFormValidator<T>> _asyncValidators;
  final List<FormError> _formErrors = <FormError>[];
  final StreamController<FormValidationState> _validationStateController =
      StreamController<FormValidationState>.broadcast(sync: true);
  FormValidationState _validationState = FormValidationState.idle;
  int _validationGeneration = 0;

  /// Controls automatic validation for registered fields.
  final FormValidationMode validationMode;

  /// Waits before invoking form-level asynchronous validators.
  final Duration? asyncValidationDebounce;

  /// Registered generated fields by model field name.
  Map<String, FormFieldState<Object?>> get fields => _fields;

  /// Current validation result without triggering another validation pass.
  FormValidationResult get validation => _buildValidationResult();

  /// Whether all fields are currently valid.
  bool get isValid => validation.isValid;

  /// Current synchronous/asynchronous validation state.
  FormValidationState get validationState => _validationState;

  /// Emits whenever [validationState] changes.
  Stream<FormValidationState> get validationStates =>
      _validationStateController.stream;

  /// All current field errors.
  List<FormError> get errors => validation.errors;

  /// Validates every registered field.
  bool validate() {
    _validationGeneration++;
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

    _setValidationState(
      validation.isValid
          ? FormValidationState.valid
          : FormValidationState.invalid,
    );
    return validation.isValid;
  }

  /// Runs field and form validators, including asynchronous validators.
  Future<bool> validateAsync() async {
    final int generation = ++_validationGeneration;
    _setValidationState(FormValidationState.validating);
    final List<bool> fieldResults = await Future.wait(
      _fields.values
          .map((FormFieldState<Object?> field) => field.validateAsync()),
    );
    if (generation != _validationGeneration) return false;
    if (fieldResults.any((bool result) => !result)) {
      _setValidationState(FormValidationState.invalid);
      return false;
    }

    _formErrors.clear();
    final T model = _builder();
    for (final FormValidator<T> validator in _validators) {
      final FormError? error = validator(model);
      if (error != null) _formErrors.add(error);
    }
    final Duration? debounce = asyncValidationDebounce;
    if (debounce != null && debounce > Duration.zero) {
      await Future<void>.delayed(debounce);
    }
    if (generation != _validationGeneration) return false;
    for (final AsyncFormValidator<T> validator in _asyncValidators) {
      try {
        final FormError? error = await validator(model);
        if (error != null) _formErrors.add(error);
      } on Object {
        _formErrors.add(const FormError(
          code: 'validation.exception',
          message: 'No se pudo validar el formulario',
        ));
      }
      if (generation != _validationGeneration) return false;
    }
    _setValidationState(
      validation.isValid
          ? FormValidationState.valid
          : FormValidationState.invalid,
    );
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

  /// Validates asynchronously and builds the model only when valid.
  Future<T> buildAsync() async {
    if (!await validateAsync()) {
      throw StateError('Cannot build an invalid form');
    }
    return _builder();
  }

  /// Applies field errors returned by a REST endpoint.
  void applyRestError(RestHttpException error) {
    final RestProblemDetails problem = error.problem;
    final String prefix =
        problem.code == null ? 'server' : 'server.${problem.code}';
    applyFieldErrors(problem.validationErrors, codePrefix: prefix);
  }

  /// Applies server messages to matching generated fields.
  void applyFieldErrors(
    Map<String, List<String>> fieldErrors, {
    String codePrefix = 'server.validation',
  }) {
    _validationGeneration++;
    for (final MapEntry<String, List<String>> entry in fieldErrors.entries) {
      final FormFieldState<Object?>? field = _fields[entry.key];
      final List<FormError> errors = <FormError>[
        for (final String message in entry.value)
          FormError(code: codePrefix, message: message),
      ];
      if (field == null) {
        _formErrors.addAll(errors);
      } else {
        field.setExternalErrors(errors);
      }
    }
    _setValidationState(FormValidationState.invalid);
  }

  /// Marks every registered field as touched.
  void touchAll() {
    for (final FormFieldState<Object?> field in _fields.values) {
      field.touch();
    }
  }

  /// Restores every registered field to its initial state.
  void reset() {
    _validationGeneration++;
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
    await _validationStateController.close();
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

  void _setValidationState(FormValidationState state) {
    _validationState = state;
    if (!_validationStateController.isClosed) {
      _validationStateController.add(state);
    }
  }
}
