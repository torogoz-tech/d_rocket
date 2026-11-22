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

  /// Compares the current value with another value using [comparison].
  static FormValidator<T> compare<T>(
    T? Function(T? value) other,
    int Function(T? left, T? right) comparison, {
    String code = 'comparison.invalid',
    String message = 'La comparación no es válida',
  }) {
    return (T? value) => comparison(value, other(value)) == 0
        ? null
        : FormError(code: code, message: message);
  }

  /// Requires a string or iterable value to contain [expected].
  static FormValidator<Object?> contains(
    Object? expected, {
    String code = 'contains.invalid',
    String message = 'El valor no contiene el elemento requerido',
  }) {
    return (Object? value) {
      final bool found = value is String
          ? value.contains('$expected')
          : value is Iterable<Object?> && value.contains(expected);
      return found ? null : FormError(code: code, message: message);
    };
  }

  /// Validates a card number with the Luhn checksum.
  static FormValidator<String> creditCard({
    String code = 'credit_card.invalid',
    String message = 'El número de tarjeta no es válido',
  }) {
    return (String? value) {
      final String digits = value?.replaceAll(RegExp(r'\s|-'), '') ?? '';
      if (digits.length < 12 || !RegExp(r'^\d+$').hasMatch(digits)) {
        return FormError(code: code, message: message);
      }
      int sum = 0;
      bool doubleDigit = false;
      for (int index = digits.length - 1; index >= 0; index--) {
        int digit = int.parse(digits[index]);
        if (doubleDigit) {
          digit *= 2;
          if (digit > 9) digit -= 9;
        }
        sum += digit;
        doubleDigit = !doubleDigit;
      }
      return sum % 10 == 0
          ? null
          : FormError(code: code, message: message);
    };
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

