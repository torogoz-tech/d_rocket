import 'package:http/http.dart' as http;

class RedirectingStreamHttpClient extends http.BaseClient {
  RedirectingStreamHttpClient(this.responses);

  final List<http.StreamedResponse> responses;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  int _index = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return responses[_index++];
  }

  @override
  void close() {}
}
