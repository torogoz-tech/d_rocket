import 'dart:convert';

import 'package:http/http.dart' as http;

class StreamPolicyHttpClient extends http.BaseClient {
  StreamPolicyHttpClient({this.statusCode = 200});

  final int statusCode;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('downloaded')),
      statusCode,
      headers: const <String, String>{
        'content-type': 'application/octet-stream'
      },
    );
  }

  @override
  void close() {}
}
