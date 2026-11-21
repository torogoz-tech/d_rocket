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
        'code': 'validation.failed',
        'traceId': 'trace-body',
        'errors': <String, Object?>{
          'email': <String>['Invalid email'],
          'name': 'Required',
        },
      },
    );

    expect(problem.status, 422);
    expect(problem.title, 'Validation failed');
    expect(problem.code, 'validation.failed');
    expect(problem.traceId, 'trace-body');
    expect(problem.validationErrors['email'], <String>['Invalid email']);
    expect(problem.validationErrors['name'], <String>['Required']);
    expect(problem.extensions['errors'], isNotNull);
  });

  test('preserves the existing raw problemDetails API', () {
    final Map<String, dynamic> body = <String, dynamic>{'detail': 'Nope'};
    final RestHttpException error = RestHttpException(
      statusCode: 400,
      request: const RestRequest(method: 'GET', path: '/items'),
      responseHeaders: const <String, String>{
        'x-trace-id': 'trace-header',
        'x-request-id': 'request-header',
      },
      errorBody: body,
    );

    expect(error.problemDetails, same(body));
    expect(error.problem.detail, 'Nope');
    expect(error.traceId, 'trace-header');
    expect(error.requestId, 'request-header');
  });
}
