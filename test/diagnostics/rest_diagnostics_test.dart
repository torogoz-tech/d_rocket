import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  final diagnostics = DrocketDiagnostics.instance;

  setUp(() {
    diagnostics.clear();
    diagnostics.configure(
      enabled: true,
      publishToVmService: false,
      includeSensitiveData: true,
    );
  });

  tearDown(() {
    diagnostics.clear();
    diagnostics.configure(enabled: false, publishToVmService: true);
  });

  test('captures structured request and response with redacted secrets',
      () async {
    final request = RestRequest(
      method: 'POST',
      path: '/events',
      baseUrl: 'https://api.example.test',
      headers: const <String, String>{
        'authorization': 'Bearer secret',
        'content-type': 'application/json',
      },
      body: '{"amount":12.50}',
    );
    final client = DiagnosticHttpClient(_FakeHttpClient(request));

    await client.execute(
      request,
      decoder: (body) => body,
    );

    final event = diagnostics.snapshot.single;
    final metadata = event.metadata;
    final requestPayload = metadata['request']! as Map<String, Object?>;
    final responsePayload = metadata['response']! as Map<String, Object?>;
    final requestHeaders = requestPayload['headers']! as Map<String, String>;

    expect(event.category, DiagnosticCategory.rest);
    expect(event.operation, 'POST');
    expect(event.statusCode, 201);
    expect(requestPayload['url'], 'https://api.example.test/events');
    expect(requestPayload['body'], '{"amount":12.50}');
    expect(requestHeaders['authorization'], '<redacted>');
    expect(requestHeaders['content-type'], 'application/json');
    expect(responsePayload['statusCode'], 201);
    expect(responsePayload['body'], '{"id":"evt-1"}');
  });

  test('hides bodies when sensitive data is disabled', () async {
    diagnostics.configure(includeSensitiveData: false);
    final request =
        RestRequest(method: 'POST', path: '/events', body: 'secret');
    final client = DiagnosticHttpClient(_FakeHttpClient(request));

    await client.execute(request, decoder: (body) => body);

    final payload = diagnostics.snapshot.single.metadata['request']!
        as Map<String, Object?>;
    expect(payload['body'], '<hidden>');
    expect(payload['bodyLength'], 6);
  });

  test('captures HTTP and network failures as failed events', () async {
    final request = RestRequest(method: 'GET', path: '/events');
    final httpError = RestHttpException(
      statusCode: 503,
      reasonPhrase: 'Unavailable',
      rawBody: '{"error":"down"}',
      responseHeaders: const <String, String>{'x-trace-id': 'trace-503'},
      errorBody: const <String, Object?>{
        'code': 'service.unavailable',
        'errors': <String, Object?>{
          'field': <String>['Invalid']
        },
      },
      request: request,
    );
    final httpClient = DiagnosticHttpClient(
      _FakeHttpClient(request, error: httpError),
    );

    await expectLater(
      httpClient.execute(request, decoder: (body) => body),
      throwsA(same(httpError)),
    );
    expect(diagnostics.snapshot.single.success, isFalse);
    expect(diagnostics.snapshot.single.statusCode, 503);
    expect(
      (diagnostics.snapshot.single.metadata['response']!
          as Map<String, Object?>)['body'],
      '{"error":"down"}',
    );
    final Map<String, Object?> errorResponse = diagnostics
        .snapshot.single.metadata['response']! as Map<String, Object?>;
    expect(errorResponse['code'], 'service.unavailable');
    expect(errorResponse['traceId'], 'trace-503');
    expect(errorResponse['validationErrors'], isNotNull);

    diagnostics.clear();
    final networkError = NetworkException('timeout');
    final networkClient = DiagnosticHttpClient(
      _FakeHttpClient(request, error: networkError),
    );
    await expectLater(
      networkClient.execute(request, decoder: (body) => body),
      throwsA(same(networkError)),
    );
    expect(diagnostics.snapshot.single.success, isFalse);
    expect(diagnostics.snapshot.single.statusCode, isNull);
    expect(diagnostics.snapshot.single.error, contains('timeout'));
  });
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.request, {this.error});

  final RestRequest request;
  final Object? error;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    if (error != null) throw error!;
    return RestResponse<dynamic>(
      statusCode: 201,
      reasonPhrase: 'Created',
      headers: const <String, String>{'content-type': 'application/json'},
      body: const <String, Object?>{'id': 'evt-1'},
      rawBody: '{"id":"evt-1"}',
      request: this.request,
    );
  }

  @override
  Future<void> close() async {}
}
