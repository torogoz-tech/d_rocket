import 'package:d_rocket/d_rocket.dart';

class ContextualRetryClient implements HttpClient {
  ContextualRetryClient({required this.failuresBeforeSuccess});

  final int failuresBeforeSuccess;
  final List<RestRequest> requests = <RestRequest>[];

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (requests.length <= failuresBeforeSuccess) {
      throw NetworkException('temporary network failure');
    }
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{},
      body: const <String, Object?>{'ok': true},
      rawBody: '{"ok":true}',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}
