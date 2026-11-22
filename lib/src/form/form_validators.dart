import 'form_error.dart';
import 'form_validator.dart';

/// Reusable validators for rules that involve more than one form value.
class FormValidators {
  const FormValidators._();

  /// Requires a boolean field to be true.
  static FormValidator<T> requiredTrue<T>({
    String code = 'required.true',
    String message = 'Este valor debe estar activo',
  }) {
    return (T? value) => value == true
        ? null
        : FormError(code: code, message: message);
  }

  /// Requires two values to be equal.
  static FormValidator<T> matches<T>(
    T? Function(T? value) other, {
    String code = 'matches.invalid',
    String message = 'Los valores no coinciden',
  }) {
    return (T? value) => value == other(value)
        ? null
        : FormError(code: code, message: message);
  }

  /// Requires a value to be contained in [allowed].
  static FormValidator<T> oneOf<T>(
    Iterable<T> allowed, {
    String code = 'membership.invalid',
    String message = 'El valor no está permitido',
  }) {
    final Set<T> values = allowed.toSet();
    return (T? value) => values.contains(value)
        ? null
        : FormError(code: code, message: message);
  }

  /// Requires a numeric value to fall within an inclusive range.
  static FormValidator<num> range({
    num? min,
    num? max,
    String code = 'range.invalid',
    String message = 'El valor está fuera de rango',
  }) {
    return (num? value) {
      if (value == null) return null;
      if (min != null && value < min) {
        return FormError(code: code, message: message);
      }
      if (max != null && value > max) {
        return FormError(code: code, message: message);
      }
      return null;
    };
  }
}

