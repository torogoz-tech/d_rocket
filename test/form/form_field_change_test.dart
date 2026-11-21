import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('emits typed and raw values for control changes', () async {
    final FormFieldState<int> field = FormFieldState<int>();
    final Future<FormFieldChange<int>> change = field.changes.first;

    field.setRawValue('42');

    final FormFieldChange<int> emitted = await change;
    expect(emitted.value, isNull);
    expect(emitted.rawValue, '42');
    await field.dispose();
  });
}
