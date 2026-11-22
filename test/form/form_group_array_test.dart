import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('FormGroup supports nested controls and dynamic registration', () async {
    final FormGroup group = FormGroup(
      controls: <String, Object>{
        'email': FormFieldState<String>(initialValue: 'a@example.com'),
        'profile': FormGroup(
          controls: <String, Object>{
            'name': FormFieldState<String>(initialValue: 'Ada'),
          },
        ),
      },
    );

    expect(group.value, <String, Object?>{
      'email': 'a@example.com',
      'profile': <String, Object?>{'name': 'Ada'},
    });
    expect(group.isPristine, isTrue);
    group.add('active', FormFieldState<bool>(initialValue: true));
    group.control('email').setValue('changed');
    expect(group.isDirty, isTrue);
    expect(await group.validateAsync(), isTrue);
    group.remove('active');
    expect(group.value.containsKey('active'), isFalse);
    await group.dispose();
  });

  test('FormArray supports add/remove and async validation', () async {
    final FormArray array = FormArray(
      controls: <Object>[
        FormFieldState<String>(initialValue: 'one'),
      ],
    );
    array.add(FormFieldState<String>(initialValue: 'two'));

    expect(array.value, <Object?>['one', 'two']);
    expect(await array.validateAsync(), isTrue);
    final Object removed = array.removeAt(0);
    await (removed as FormFieldState<Object?>).dispose();
    expect(array.value, <Object?>['two']);
    await array.dispose();
  });
}
