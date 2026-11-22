import 'dart:async';

import 'form_field_change.dart';
import 'form_error.dart';
import 'form_validation_mode.dart';
import 'form_validation_state.dart';
import 'form_validator.dart';
import 'form_value_parser.dart';

/// Holds the typed and raw state of one generated form field.
class FormFieldState<T> {
  /// Creates a field state with optional parsing and validators.
  FormFieldState({
    T? initialValue,
    this.parser,
    List<FormValidator<T>>? validators,
    List<AsyncFormValidator<T>>? asyncValidators,
    this.asyncValidationDebounce,
    this.validationMode = FormValidationMode.manual,
    bool enabled = true,
  })  : _initialValue = initialValue,
        _isEnabled = enabled,
        _value = initialValue,
        _rawValue = initialValue,
        _validators = List<FormValidator<T>>.unmodifiable(
          validators ?? <FormValidator<T>>[],
        ),
        _asyncValidators = List<AsyncFormValidator<T>>.unmodifiable(
          asyncValidators ?? <AsyncFormValidator<T>>[],
        );

  final T? _initialValue;
  final List<FormValidator<T>> _validators;
  final List<AsyncFormValidator<T>> _asyncValidators;
  final List<FormError> _errors = <FormError>[];
  final List<FormError> _externalErrors = <FormError>[];
  final StreamController<FormFieldChange<T>> _changeController =
      StreamController<FormFieldChange<T>>.broadcast();
  final StreamController<FormValidationState> _validationStateController =
      StreamController<FormValidationState>.broadcast(sync: true);
  T? _value;
  Object? _rawValue;
  bool _isTouched = false;
  bool _isEnabled;
  bool _isDisposed = false;
  int _validationGeneration = 0;
  FormValidationState _validationState = FormValidationState.idle;

  /// Converts raw values before validation.
  final FormValueParser<T>? parser;

  /// Waits before invoking asynchronous validators after a value change.
  final Duration? asyncValidationDebounce;

  /// Controls automatic validation for this field.
  FormValidationMode validationMode;

  /// Current typed value.
  T? get value => _value;

  /// Current value received from a control before conversion.
  Object? get rawValue => _rawValue;

  /// All current validation errors in declaration order.
  List<FormError> get errors => List<FormError>.unmodifiable(
        <FormError>[..._errors, ..._externalErrors],
      );

  /// First current error message, if any.
  String? get error => errors.isEmpty ? null : errors.first.message;

  /// First current error code, if any.
  String? get errorCode => errors.isEmpty ? null : errors.first.code;

  /// Whether this field currently has one or more errors.
  bool get hasError => _errors.isNotEmpty || _externalErrors.isNotEmpty;

  /// Current synchronous/asynchronous validation state.
  FormValidationState get validationState => _validationState;

  /// Emits whenever [validationState] changes.
  Stream<FormValidationState> get validationStates =>
      _validationStateController.stream;

  /// Whether a user or control has interacted with this field.
  bool get isTouched => _isTouched;

  /// Whether this field participates in value changes and validation.
  bool get isEnabled => _isEnabled;

  /// Disables the field and cancels any pending asynchronous validation.
  void disable() => setEnabled(false);

  /// Enables the field for subsequent changes and validation.
  void enable() => setEnabled(true);

  /// Changes whether this field participates in validation.
  void setEnabled(bool enabled) {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    ++_validationGeneration;
    if (!enabled) {
      _errors.clear();
      _externalErrors.clear();
      _setValidationState(FormValidationState.idle);
    }
    _emitChange();
  }

  /// Whether the current value differs from the initial value.
  bool get isDirty => _value != _initialValue;

  /// Emits after a control changes this field.
  Stream<FormFieldChange<T>> get changes => _changeController.stream;

  /// Creates a callback for controls whose callback value is non-nullable.
  void Function(T) bind() {
    return (T nextValue) {
      setValue(nextValue);
    };
  }

  /// Creates a callback for controls whose callback value is nullable.
  void Function(T?) bindNullable() {
    return (T? nextValue) {
      setValue(nextValue);
    };
  }

  /// Creates a callback for controls that emit an untyped raw value.
  void Function(Object?) bindRaw() {
    return (Object? nextRawValue) {
      setRawValue(nextRawValue);
    };
  }

  /// Sets a typed value and clears errors caused by the previous value.
  void setValue(T? nextValue) {
    if (!_isEnabled) return;
    _value = nextValue;
    _rawValue = nextValue;
    _isTouched = true;
    _errors.clear();
    _externalErrors.clear();

    if (nextValue == null && null is! T && _validators.isEmpty) {
      _errors.add(_invalidConversionError);
    }

    if (validationMode == FormValidationMode.onChange) {
      if (_asyncValidators.isEmpty) {
        validate();
      } else {
        unawaited(validateAsync());
      }
    }
    _emitChange();
  }

  /// Sets a raw control value and converts it when a parser is available.
  void setRawValue(Object? nextRawValue) {
    if (!_isEnabled) return;
    _rawValue = nextRawValue;
    _isTouched = true;
    _errors.clear();
    _externalErrors.clear();

    if (parser == null) {
      try {
        if (nextRawValue == null && null is! T) {
          throw const FormatException(
              'A null value is not valid for this field');
        }
        _value = nextRawValue as T?;
      } on Object {
        _value = null;
        _errors.add(_invalidConversionError);
      }
    } else {
      try {
        _value = parser!.parse(nextRawValue);
      } on Object {
        _value = null;
        _errors.add(_invalidConversionError);
      }
    }

    if (validationMode == FormValidationMode.onChange) {
      if (_asyncValidators.isEmpty) {
        validate();
      } else {
        unawaited(validateAsync());
      }
    }
    _emitChange();
  }

  /// Marks the field as interacted with and validates in blur mode.
  void touch() {
    if (!_isEnabled) return;
    _isTouched = true;

    if (validationMode == FormValidationMode.onBlur) {
      if (_asyncValidators.isEmpty) {
        validate();
      } else {
        unawaited(validateAsync());
      }
    }
  }

  /// Runs all validators and returns whether the field is valid.
  bool validate() {
    if (!_isEnabled) {
      _setValidationState(FormValidationState.idle);
      return true;
    }
    final FormError? conversionError = _errors
        .where((FormError item) => item.code == 'conversion.invalid')
        .cast<FormError?>()
        .firstWhere(
          (FormError? item) => item != null,
          orElse: () => null,
        );

    _errors.clear();
    if (conversionError != null) {
      _errors.add(conversionError);
      return false;
    }

    if (_value == null && null is! T && _validators.isEmpty) {
      _errors.add(_invalidConversionError);
      return false;
    }

    for (final FormValidator<T> validator in _validators) {
      final FormError? validationError = validator(_value);
      if (validationError != null) {
        _errors.add(validationError);
      }
    }

    _setValidationState(
      _errors.isEmpty && _externalErrors.isEmpty
          ? FormValidationState.valid
          : FormValidationState.invalid,
    );
    return _errors.isEmpty && _externalErrors.isEmpty;
  }

  /// Runs synchronous and asynchronous validators with optional debounce.
  Future<bool> validateAsync() async {
    if (!_isEnabled) {
      _setValidationState(FormValidationState.idle);
      return true;
    }
    final int generation = ++_validationGeneration;
    _setValidationState(FormValidationState.validating);
    final Duration? debounce = asyncValidationDebounce;
    if (debounce != null && debounce > Duration.zero) {
      await Future<void>.delayed(debounce);
      if (generation != _validationGeneration) return false;
    }

    if (!validate()) return false;
    for (final AsyncFormValidator<T> validator in _asyncValidators) {
      try {
        final FormError? error = await validator(_value);
        if (generation != _validationGeneration) return false;
        if (error != null) _errors.add(error);
      } on Object {
        if (generation != _validationGeneration) return false;
        _errors.add(const FormError(
          code: 'validation.exception',
          message: 'No se pudo validar el valor',
        ));
      }
    }
    _setValidationState(
      _errors.isEmpty && _externalErrors.isEmpty
          ? FormValidationState.valid
          : FormValidationState.invalid,
    );
    return _errors.isEmpty && _externalErrors.isEmpty;
  }

  /// Adds server-side errors until the field receives a new value or resets.
  void setExternalErrors(List<FormError> errors) {
    _externalErrors
      ..clear()
      ..addAll(errors);
    _setValidationState(
      _externalErrors.isEmpty
          ? FormValidationState.valid
          : FormValidationState.invalid,
    );
    _emitChange();
  }

  static const FormError _invalidConversionError = FormError(
    code: 'conversion.invalid',
    message: 'El valor no es válido',
  );

  /// Restores the initial value and clears interaction state.
  void reset() {
    _value = _initialValue;
    _rawValue = _initialValue;
    _errors.clear();
    _externalErrors.clear();
    _isTouched = false;
    ++_validationGeneration;
    _setValidationState(FormValidationState.idle);
    _emitChange();
  }

  /// Releases the field's change stream.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _changeController.close();
    await _validationStateController.close();
  }

  void _emitChange() {
    if (!_isDisposed) {
      _changeController.add(
        FormFieldChange<T>(value: _value, rawValue: _rawValue),
      );
    }
  }

  void _setValidationState(FormValidationState state) {
    _validationState = state;
    if (!_isDisposed && !_validationStateController.isClosed) {
      _validationStateController.add(state);
    }
  }
}
