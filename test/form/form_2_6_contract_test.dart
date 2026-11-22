import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('disabled fields do not change or participate in validation', () {
    final FormFieldState<String> field = FormFieldState<String>(
      initialValue: 'initial',
      validators: <FormValidator<String>>[
        (String? value) => value == 'ok'
            ? null
            : const FormError(code: 'invalid', message: 'invalid'),
      ],
    );

    field.disable();
    field.setValue('bad');

    expect(field.value, 'initial');
    expect(field.validate(), isTrue);
    expect(field.validationState, FormValidationState.idle);

    field.enable();
    field.setValue('bad');
    expect(field.validate(), isFalse);
    expect(field.errorCode, 'invalid');
  });

  test('nested controls can be enabled and disabled together', () {
    final FormGroup group = FormGroup(
      controls: <String, Object>{
        'name': FormFieldState<String>(initialValue: 'Ada'),
        'items': FormArray(
          controls: <Object>[FormFieldState<int>(initialValue: 1)],
        ),
      },
    );

    group.setEnabled(false);
    expect(group.isEnabled, isFalse);
    expect(group.control('name').isEnabled, isFalse);
    expect(group.validationState, FormValidationState.valid);

    group.setEnabled(true);
    expect(group.isEnabled, isTrue);
  });

  test('rest field paths accept dotted and bracket notation', () {
    final FormState<Object> form = FormState<Object>(
      fields: <String, FormFieldState<Object?>>{
        'email': FormFieldState<Object?>(initialValue: null),
      },
      builder: () => Object(),
    );

    expect(form.fields.containsKey('email'), isTrue);

    form.applyFieldErrors(<String, List<String>>{
      'user["email"]': <String>['Already used'],
    });

    expect(form.fields['email']!.error, 'Already used');
  });

  test('reusable cross-field validators cover common rules', () {
    expect(FormValidators.requiredTrue<bool>()(true), isNull);
    expect(FormValidators.requiredTrue<bool>()(false), isNotNull);
    expect(FormValidators.oneOf<String>(<String>['a'])('a'), isNull);
    expect(FormValidators.oneOf<String>(<String>['a'])('b'), isNotNull);
    expect(FormValidators.range(min: 1, max: 3)(2), isNull);
    expect(FormValidators.range(min: 1, max: 3)(4), isNotNull);
  });
}
