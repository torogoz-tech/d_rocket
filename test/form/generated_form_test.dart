import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/auth_client_fixture.dart';
import '../fixtures/login_request.dart';
import '../support/request_capture_http_client.dart';

void main() {
  test('generated form validates, builds and serializes LoginRequest', () {
    final LoginRequestForm form = LoginRequestForm();

    expect(LoginRequestForm.definitions.map((field) => field.name),
        <String>['email', 'password']);
    expect(LoginRequestForm.definitions.first.label, 'Correo electrónico');
    expect(LoginRequestForm.definitions.last.input, FormInput.password);

    form.email.bind()('person@example.com');
    form.password.bind()('strong-password');

    expect(form.validate(), isTrue);
    final LoginRequest request = form.build();
    expect(request.toJson(), <String, dynamic>{
      'email': 'person@example.com',
      'password': 'strong-password',
    });
  });

  test('generated form keeps model validation errors by field', () {
    final LoginRequestForm form = LoginRequestForm();

    form.email.bind()('invalid');
    form.password.bind()('short');

    expect(form.validate(), isFalse);
    expect(form.email.errorCode, 'email.invalid');
    expect(form.password.errorCode, 'length.invalid');
    expect(form.state.validation.fieldErrors.keys,
        containsAll(<String>['email', 'password']));
  });

  test('generated REST client accepts the generated model body', () async {
    registerLoginRequestSerializer();
    final RequestCaptureHttpClient transport = RequestCaptureHttpClient(
      RestResponse<dynamic>(
        statusCode: 200,
        headers: const <String, String>{},
        body: <String, dynamic>{'ok': true},
        rawBody: '{"ok":true}',
        request: RestRequest(method: 'GET', path: '/placeholder'),
      ),
    );
    final AuthClientFixture client = createAuthClientFixture(
      config: RestClientConfig(client: transport),
    );

    await client.login(
      LoginRequest(email: 'person@example.com', password: 'strong-password'),
    );

    expect(transport.lastRequest?.method, 'POST');
    expect(transport.lastRequest?.path, '/auth/login');
    expect(transport.lastRequest?.bodyAsString, contains('person@example.com'));
    expect(transport.lastRequest?.bodyAsString, contains('strong-password'));
  });
}
