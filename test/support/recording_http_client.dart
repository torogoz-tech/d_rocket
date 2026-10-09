import 'package:d_rocket/d_rocket.dart';

class RecordingHttpClient implements HttpClient {
  RecordingHttpClient(this.calls, this.name, [this.inner]);

  final List<String> calls;
  final String name;
  final HttpClient? inner;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    calls.add(name);
    if (inner != null) {
      return inner!
          .execute(request, decoder: decoder, cancelToken: cancelToken);
    }
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: <String, Object?>{'ok': true},
      rawBody: '{"ok":true}',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}
