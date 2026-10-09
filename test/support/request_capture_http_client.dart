import 'package:d_rocket/d_rocket.dart';

class RequestCaptureHttpClient implements HttpClient {
  RequestCaptureHttpClient(this.response);

  final RestResponse<dynamic> response;
  RestRequest? lastRequest;
  int calls = 0;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    lastRequest = request;
    calls++;
    return response;
  }

  @override
  Future<void> close() async {}
}
