import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('exposes typed RFC 7807 fields and validation messages', () {
    final RestProblemDetails problem = RestProblemDetails.fromJson(
      <String, Object?>{
        'type': 'https://example.test/validation',
        'title': 'Validation failed',
        'status': 422,
        'detail': 'The request is invalid',
        'instance': '/orders/1',
        'errors': <String, Object?>{
          'email': <String>['Invalid email'],
          'name': 'Required',
        },
        'traceId': 'abc',
      },
    );

    expect(problem.status, 422);
    expect(problem.title, 'Validation failed');
    expect(problem.validationErrors['email'], <String>['Invalid email']);
    expect(problem.validationErrors['name'], <String>['Required']);
    expect(problem.extensions['traceId'], 'abc');
  });

  test('preserves the existing raw problemDetails API', () {
    final Map<String, dynamic> body = <String, dynamic>{'detail': 'Nope'};
    final RestHttpException error = RestHttpException(
      statusCode: 400,
      request: const RestRequest(method: 'GET', path: '/items'),
      errorBody: body,
    );

    expect(error.problemDetails, same(body));
    expect(error.problem.detail, 'Nope');
  });
}
