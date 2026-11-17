import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('form annotation contract', () {
    test('Form exposes its default opt-in metadata', () {
      const Form annotation = Form();

      expect(annotation, isA<Form>());
    });

    test('FormField preserves display metadata and input kind', () {
      const FormField annotation = FormField(
        label: 'Correo electrónico',
        order: 2,
        input: FormInput.email,
      );

      expect(annotation.label, 'Correo electrónico');
      expect(annotation.order, 2);
      expect(annotation.input, FormInput.email);
    });

    test('validator annotations preserve custom messages and codes', () {
      const Required required = Required(
        message: 'El correo es obligatorio',
        code: 'email.required',
      );
      const Email email = Email(
        message: 'El correo no es válido',
        code: 'email.invalid',
      );
      const Length length = Length(
        min: 8,
        max: 64,
        message: 'Longitud inválida',
        code: 'password.length',
      );
      const Pattern pattern = Pattern(
        expression: r'^[A-Z]+$',
        message: 'Solo se permiten mayúsculas',
      );
      const Range range = Range(
        min: 1,
        max: 10,
        message: 'Fuera de rango',
      );

      expect(required.message, 'El correo es obligatorio');
      expect(required.code, 'email.required');
      expect(email.message, 'El correo no es válido');
      expect(email.code, 'email.invalid');
      expect(length.min, 8);
      expect(length.max, 64);
      expect(pattern.expression, r'^[A-Z]+$');
      expect(range.min, 1);
      expect(range.max, 10);
    });

    test('FormInput exposes the first supported control kinds', () {
      expect(
        FormInput.values,
        containsAll(<FormInput>[
          FormInput.text,
          FormInput.password,
          FormInput.email,
          FormInput.number,
          FormInput.boolean,
          FormInput.date,
        ]),
      );
    });
  });
}
