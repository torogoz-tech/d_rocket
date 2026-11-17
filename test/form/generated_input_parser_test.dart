import 'package:test/test.dart';

import '../fixtures/form_input_types.dart';

void main() {
  test('generated raw parsers report invalid numeric, boolean and date input',
      () {
    final FormInputTypesForm form = FormInputTypesForm();

    form.amount.bindRaw()('not-a-number');
    form.active.bindRaw()('not-a-boolean');
    form.date.bindRaw()('not-a-date');

    expect(form.amount.errorCode, 'conversion.invalid');
    expect(form.active.errorCode, 'conversion.invalid');
    expect(form.date.errorCode, 'conversion.invalid');
  });

  test('generated non-nullable parsers reject null raw input', () {
    final FormInputTypesForm form = FormInputTypesForm();

    form.amount.bindRaw()(null);
    form.active.bindRaw()(null);
    form.date.bindRaw()(null);

    expect(form.amount.errorCode, 'conversion.invalid');
    expect(form.active.errorCode, 'conversion.invalid');
    expect(form.date.errorCode, 'conversion.invalid');
  });

  test('generated forms reject unset non-nullable fields before build', () {
    final FormInputTypesForm form = FormInputTypesForm();

    expect(form.validate(), isFalse);
    expect(form.amount.errorCode, 'conversion.invalid');
    expect(form.active.errorCode, 'conversion.invalid');
    expect(form.date.errorCode, 'conversion.invalid');
    expect(() => form.build(), throwsStateError);
  });

  test('generated forms reject typed null assignments before build', () {
    final FormInputTypesForm form = FormInputTypesForm();

    form.amount.setValue(null);
    form.active.setValue(null);
    form.date.setValue(null);

    expect(form.validate(), isFalse);
    expect(form.state.errors, hasLength(3));
    expect(() => form.build(), throwsStateError);
  });
}
