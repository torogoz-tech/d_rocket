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

    test('Uuid exposes general and version-specific metadata', () {
      const Uuid general = Uuid();
      const Uuid v4 = Uuid(version: UuidVersion.v4);
      const Uuid custom = Uuid(
        version: UuidVersion.v7,
        message: 'Identificador inválido',
        code: 'request.id.uuid',
      );

      expect(general.version, isNull);
      expect(general.message, isNull);
      expect(general.code, 'uuid.invalid');
      expect(v4.version, UuidVersion.v4);
      expect(custom.version, UuidVersion.v7);
      expect(custom.message, 'Identificador inválido');
      expect(custom.code, 'request.id.uuid');
      expect(UuidVersion.values, hasLength(8));
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
