import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('FormFieldState', () {
    test('bind updates a typed value and marks the field as touched', () {
      final FormFieldState<String> field = FormFieldState<String>(
        initialValue: 'old@example.com',
      );

      field.bind()('new@example.com');

      expect(field.value, 'new@example.com');
      expect(field.isTouched, isTrue);
      expect(field.hasError, isFalse);
    });

    test('bindNullable accepts a null value without an unsafe cast', () {
      final FormFieldState<bool?> field = FormFieldState<bool?>(
        initialValue: true,
      );

      field.bindNullable()(null);

      expect(field.value, isNull);
      expect(field.isTouched, isTrue);
    });

    test('validation exposes the first error message and stable code', () {
      final FormFieldState<String> field = FormFieldState<String>(
        validators: <FormValidator<String>>[
          (String? value) => value == null || value.isEmpty
              ? const FormError(
                  code: 'email.required',
                  message: 'El correo es obligatorio',
                )
              : null,
        ],
      );

      expect(field.validate(), isFalse);
      expect(field.error, 'El correo es obligatorio');
      expect(field.errorCode, 'email.required');
      expect(field.errors, hasLength(1));
    });

    test('invalid numeric raw input becomes a conversion error', () {
      final FormFieldState<int> field = FormFieldState<int>(
        parser: FormValueParser<int>(
          parse: (Object? rawValue) => int.parse(rawValue! as String),
        ),
      );

      field.setRawValue('not-a-number');

      expect(field.value, isNull);
      expect(field.errorCode, 'conversion.invalid');
      expect(field.error, 'El valor no es válido');
      expect(field.isTouched, isTrue);
    });

    test('invalid date input becomes a conversion error', () {
      final FormFieldState<DateTime> field = FormFieldState<DateTime>(
        parser: FormValueParser<DateTime>(
          parse: (Object? rawValue) => DateTime.parse(rawValue! as String),
        ),
      );

      field.setRawValue('not-a-date');

      expect(field.value, isNull);
      expect(field.errorCode, 'conversion.invalid');
      expect(field.hasError, isTrue);
    });

    test('bindRaw connects controls with a different raw value type', () {
      final FormFieldState<int> field = FormFieldState<int>(
        parser: FormValueParser<int>(
          parse: (Object? rawValue) => int.tryParse(rawValue.toString()),
        ),
      );

      field.bindRaw()('42');

      expect(field.value, 42);
      expect(field.rawValue, '42');
    });

    test('bindRaw reports null for a non-nullable field as conversion error', () {
      final FormFieldState<int> field = FormFieldState<int>();

      field.bindRaw()(null);

      expect(field.value, isNull);
      expect(field.errorCode, 'conversion.invalid');
    });

    test('setValue reports null for a non-nullable field as conversion error',
        () {
      final FormFieldState<DateTime> field = FormFieldState<DateTime>();

      field.setValue(null);

      expect(field.value, isNull);
      expect(field.errorCode, 'conversion.invalid');
      expect(field.validate(), isFalse);
    });

    test('validation rejects an unset non-nullable field before build', () {
      final FormFieldState<int> field = FormFieldState<int>();

      expect(field.validate(), isFalse);
      expect(field.errorCode, 'conversion.invalid');
    });

    test('reset restores the initial value and clears interaction state', () {
      final FormFieldState<String> field = FormFieldState<String>(
        initialValue: 'initial',
      );

      field.bind()('changed');
      field.reset();

      expect(field.value, 'initial');
      expect(field.isTouched, isFalse);
      expect(field.errors, isEmpty);
    });
  });
}
