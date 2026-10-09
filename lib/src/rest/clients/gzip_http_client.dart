import 'dart:convert';

import '../cancel_token.dart';
import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';
import 'compressed_http_client.dart';

/// Compresses request bodies with gzip before forwarding them to [inner].
class GzipHttpClient implements HttpClient {
  /// Creates a gzip request wrapper.
  const GzipHttpClient({required this.inner});

  final HttpClient inner;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) {
    if (request.body == null) {
      return inner.execute(request, decoder: decoder, cancelToken: cancelToken);
    }
    final List<int> bytes = request.body is List<int>
        ? List<int>.from(request.body! as List<int>)
        : utf8.encode(request.body! as String);
    final RestRequest compressed = RestRequest(
      method: request.method,
      path: request.path,
      baseUrl: request.baseUrl,
      headers: <String, String>{
        ...request.headers,
        'Content-Encoding': 'gzip',
        'Accept-Encoding': 'gzip',
      },
      body: GzipCodec.encode(bytes),
      queryParameters: request.queryParameters,
      pathParameters: request.pathParameters,
      timeout: request.timeout,
      cancelToken: request.cancelToken,
    );
    return inner.execute(compressed,
        decoder: decoder, cancelToken: cancelToken);
  }

  @override
  Future<void> close() => inner.close();
}
