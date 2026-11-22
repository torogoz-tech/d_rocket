import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/multipart_client_fixture.dart';

class _MultipartHttpClient implements HttpClient {
  RestRequest? request;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    this.request = request;
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{},
      body: <String, Object?>{'ok': true},
      rawBody: '',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('generated multipart client sends bytes and content type', () async {
    final _MultipartHttpClient transport = _MultipartHttpClient();
    final MultipartClientFixture client = createMultipartClientFixture(
      config: RestClientConfig(client: transport),
    );

    await client.upload(<int>[1, 2, 3], 'Ada');

    final RestRequest request = transport.request!;
    expect(request.headers['Content-Type'], startsWith('multipart/form-data;'));
    expect(request.body, isA<List<int>>());
    final String body = utf8.decode(request.body! as List<int>);
    expect(body, contains('name="file"'));
    expect(body, contains('name="name"'));
    expect(body, contains('Ada'));
  });
}
