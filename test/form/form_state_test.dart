import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('FormState', () {
    test('validates all fields and builds the typed model', () {
      final FormFieldState<String> email = FormFieldState<String>(
        initialValue: 'user@example.com',
      );
      final FormState<String> form = FormState<String>(
        fields: <String, FormFieldState<Object?>>{'email': email},
        builder: () => email.value!,
      );

      expect(form.validate(), isTrue);
      expect(form.isValid, isTrue);
      expect(form.build(), 'user@example.com');
    });

    test('invalid validation exposes field errors and blocks build', () {
      final FormFieldState<String> email = FormFieldState<String>(
        validators: <FormValidator<String>>[
          (String? value) => value == null || value.isEmpty
              ? const FormError(
                  code: 'email.required',
                  message: 'El correo es obligatorio',
                )
              : null,
        ],
      );
      final FormState<String> form = FormState<String>(
        fields: <String, FormFieldState<Object?>>{'email': email},
        builder: () => email.value!,
      );

      expect(form.validate(), isFalse);
      expect(form.validation.fieldErrors['email'], hasLength(1));
      expect(form.errors.single.code, 'email.required');
      expect(() => form.build(), throwsStateError);
    });

    test('onChange mode validates a field when its binding changes', () {
      final FormFieldState<String> field = FormFieldState<String>(
        validators: <FormValidator<String>>[
          (String? value) => value == null || value.isEmpty
              ? const FormError(
                  code: 'required',
                  message: 'Campo requerido',
                )
              : null,
        ],
      );
      final FormState<String> form = FormState<String>(
        fields: <String, FormFieldState<Object?>>{'field': field},
        validationMode: FormValidationMode.onChange,
        builder: () => field.value!,
      );

      form.fields['field']!.setValue('');

      expect(form.fields['field']!.errorCode, 'required');
    });

    test('onBlur mode validates a field when it is touched', () {
      final FormFieldState<String> field = FormFieldState<String>(
        validators: <FormValidator<String>>[
          (String? value) => value == null || value.isEmpty
              ? const FormError(
                  code: 'required',
                  message: 'Campo requerido',
                )
              : null,
        ],
      );
      final FormState<String> form = FormState<String>(
        fields: <String, FormFieldState<Object?>>{'field': field},
        validationMode: FormValidationMode.onBlur,
        builder: () => field.value!,
      );

      form.fields['field']!.touch();

      expect(form.fields['field']!.errorCode, 'required');
    });

    test('manual mode waits for explicit form validation', () {
      final FormFieldState<String> field = FormFieldState<String>(
        validators: <FormValidator<String>>[
          (String? value) => value == null || value.isEmpty
              ? const FormError(
                  code: 'required',
                  message: 'Campo requerido',
                )
              : null,
        ],
      );
      final FormState<String> form = FormState<String>(
        fields: <String, FormFieldState<Object?>>{'field': field},
        validationMode: FormValidationMode.manual,
        builder: () => field.value!,
      );

      form.fields['field']!.setValue('');

      expect(form.fields['field']!.hasError, isFalse);
      expect(form.validate(), isFalse);
    });

    test('touchAll marks every field and reset clears the form', () {
      final FormFieldState<String> first = FormFieldState<String>(
        initialValue: 'one',
      );
      final FormFieldState<String> second = FormFieldState<String>(
        initialValue: 'two',
      );
      final FormState<List<String>> form = FormState<List<String>>(
        fields: <String, FormFieldState<Object?>>{
          'first': first,
          'second': second,
        },
        builder: () => <String>[first.value!, second.value!],
      );

      form.fields['first']!.setValue('changed');
      form.touchAll();
      form.reset();

      expect(first.isTouched, isFalse);
      expect(second.isTouched, isFalse);
      expect(first.value, 'one');
      expect(form.isValid, isTrue);
    });

    test('runs model-level validators after field validation', () {
      final FormFieldState<String> number = FormFieldState<String>(
        initialValue: '4111111111111111',
      );
      final FormFieldState<String> cvv = FormFieldState<String>(
        initialValue: '123',
      );
      final FormState<Map<String, String>> form =
          FormState<Map<String, String>>(
        fields: <String, FormFieldState<Object?>>{
          'number': number,
          'cvv': cvv,
        },
        builder: () => <String, String>{
          'number': number.value!,
          'cvv': cvv.value!,
        },
        validators: <FormValidator<Map<String, String>>>[
          (Map<String, String>? model) =>
              model!['number']!.startsWith('3') && model['cvv']!.length != 4
                  ? const FormError(
                      code: 'cvv.invalid_for_brand',
                      message: 'El CVV debe tener cuatro dígitos',
                    )
                  : null,
        ],
      );

      expect(form.validate(), isTrue);
      number.setValue('378282246310005');

      expect(form.validate(), isFalse);
      expect(form.errors.single.code, 'cvv.invalid_for_brand');
    });

    test('bindComposite updates several raw fields through their parsers', () {
      final FormFieldState<int> month = FormFieldState<int>(
        parser: FormValueParser<int>(parse: (Object? raw) => int.parse('$raw')),
      );
      final FormFieldState<int> year = FormFieldState<int>(
        parser: FormValueParser<int>(parse: (Object? raw) => int.parse('$raw')),
      );
      final FormState<List<int>> form = FormState<List<int>>(
        fields: <String, FormFieldState<Object?>>{
          'month': month,
          'year': year,
        },
        builder: () => <int>[month.value!, year.value!],
      );

      final void Function(String) bind = form.bindComposite<String>(
        (String value) => <String, Object?>{
          'month': value.substring(0, 2),
          'year': value.substring(3),
        },
      );
      bind('04/29');

      expect(month.value, 4);
      expect(year.value, 29);
    });
  });
}
