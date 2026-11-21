import 'dart:async';

import 'form_field_change.dart';
import 'form_error.dart';
import 'form_validation_mode.dart';
import 'form_value_parser.dart';

/// Produces an error when a typed value is invalid.
typedef FormValidator<T> = FormError? Function(T? value);

/// Holds the typed and raw state of one generated form field.
class FormFieldState<T> {
  /// Creates a field state with optional parsing and validators.
  FormFieldState({
    T? initialValue,
    this.parser,
    List<FormValidator<T>>? validators,
    this.validationMode = FormValidationMode.manual,
  })  : _initialValue = initialValue,
        _value = initialValue,
        _rawValue = initialValue,
        _validators = List<FormValidator<T>>.unmodifiable(
          validators ?? <FormValidator<T>>[],
        );

  final T? _initialValue;
  final List<FormValidator<T>> _validators;
  final List<FormError> _errors = <FormError>[];
  final StreamController<FormFieldChange<T>> _changeController =
      StreamController<FormFieldChange<T>>.broadcast();
  T? _value;
  Object? _rawValue;
  bool _isTouched = false;
  bool _isDisposed = false;

  /// Converts raw values before validation.
  final FormValueParser<T>? parser;

  /// Controls automatic validation for this field.
  FormValidationMode validationMode;

  /// Current typed value.
  T? get value => _value;

  /// Current value received from a control before conversion.
  Object? get rawValue => _rawValue;

  /// All current validation errors in declaration order.
  List<FormError> get errors => List<FormError>.unmodifiable(_errors);

  /// First current error message, if any.
  String? get error => _errors.isEmpty ? null : _errors.first.message;

  /// First current error code, if any.
  String? get errorCode => _errors.isEmpty ? null : _errors.first.code;

  /// Whether this field currently has one or more errors.
  bool get hasError => _errors.isNotEmpty;

  /// Whether a user or control has interacted with this field.
  bool get isTouched => _isTouched;

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
    _value = nextValue;
    _rawValue = nextValue;
    _isTouched = true;
    _errors.clear();

    if (nextValue == null && null is! T && _validators.isEmpty) {
      _errors.add(_invalidConversionError);
    }

    if (validationMode == FormValidationMode.onChange) {
      validate();
    }
    _emitChange();
  }

  /// Sets a raw control value and converts it when a parser is available.
  void setRawValue(Object? nextRawValue) {
    _rawValue = nextRawValue;
    _isTouched = true;
    _errors.clear();

    if (parser == null) {
      try {
        if (nextRawValue == null && null is! T) {
          throw const FormatException('A null value is not valid for this field');
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
      validate();
    }
    _emitChange();
  }

  /// Marks the field as interacted with and validates in blur mode.
  void touch() {
    _isTouched = true;

    if (validationMode == FormValidationMode.onBlur) {
      validate();
    }
  }

  /// Runs all validators and returns whether the field is valid.
  bool validate() {
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

    return _errors.isEmpty;
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
    _isTouched = false;
    _emitChange();
  }

  /// Releases the field's change stream.
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _changeController.close();
  }

  void _emitChange() {
    if (!_isDisposed) {
      _changeController.add(
        FormFieldChange<T>(value: _value, rawValue: _rawValue),
      );
    }
  }
}
