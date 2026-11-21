import 'package:d_rocket/d_rocket.dart';

class PolicyHttpClient implements HttpClient {
  RestRequest? lastRequest;
  final List<RestRequest> requests = <RestRequest>[];

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    lastRequest = request;
    requests.add(request);
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: <String, dynamic>{'ok': true},
      rawBody: '{"ok":true}',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}
