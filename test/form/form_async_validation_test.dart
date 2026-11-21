import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('debounces async field validation and exposes its state', () async {
    final List<FormValidationState> states = <FormValidationState>[];
    final FormFieldState<String> field = FormFieldState<String>(
      asyncValidators: <AsyncFormValidator<String>>[
        (String? value) async => value == 'taken'
            ? const FormError(
                code: 'username.taken',
                message: 'El usuario ya existe',
              )
            : null,
      ],
      asyncValidationDebounce: const Duration(milliseconds: 5),
    );
    final StreamSubscription<FormValidationState> subscription =
        field.validationStates.listen(states.add);

    field.setValue('taken');
    final Future<bool> firstValidation = field.validateAsync();
    expect(field.validationState, FormValidationState.validating);
    expect(await firstValidation, isFalse);
    expect(field.errorCode, 'username.taken');
    expect(states, contains(FormValidationState.validating));
    expect(field.validationState, FormValidationState.invalid);

    field.setValue('available');
    expect(await field.validateAsync(), isTrue);
    expect(field.validationState, FormValidationState.valid);

    await subscription.cancel();
    await field.dispose();
  });

  test('maps REST validation errors onto fields', () {
    final FormFieldState<String> email = FormFieldState<String>();
    final FormState<Map<String, String>> form = FormState<Map<String, String>>(
      fields: <String, FormFieldState<Object?>>{'email': email},
      builder: () => <String, String>{'email': email.value ?? ''},
    );
    final RestHttpException error = RestHttpException(
      statusCode: 422,
      request: const RestRequest(method: 'POST', path: '/users'),
      errorBody: const <String, Object?>{
        'code': 'validation.failed',
        'errors': <String, Object?>{
          'email': <String>['Correo inválido'],
        },
      },
    );

    form.applyRestError(error);

    expect(form.isValid, isFalse);
    expect(email.errorCode, 'server.validation.failed');
    expect(email.error, 'Correo inválido');
  });
}
