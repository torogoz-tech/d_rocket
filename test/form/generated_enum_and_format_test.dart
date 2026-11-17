import 'package:test/test.dart';

import '../fixtures/form_enum_request.dart';
import '../fixtures/form_format_request.dart';
import '../fixtures/form_status.dart';

void main() {
  test('generated enum parser converts a raw enum name', () {
    final FormEnumRequestForm form = FormEnumRequestForm();

    form.status.bindRaw()('active');

    expect(form.status.value, FormStatus.active);
    expect(form.build().status, FormStatus.active);
  });

  test('generated form parser applies existing string formats', () {
    final FormFormatRequestForm form = FormFormatRequestForm();

    form.value.bindRaw()('  HELLO ');

    expect(form.value.value, 'hello');
    expect(form.build().value, 'hello');
  });
}
