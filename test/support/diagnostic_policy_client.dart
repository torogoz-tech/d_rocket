import 'package:d_rocket/d_rocket.dart';

class DiagnosticPolicyClient implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{'DPoP': 'response-proof-secret'},
      body: const <String, Object?>{'ok': true},
      rawBody: '{"ok":true}',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}
