import '../cancel_token.dart';
import '../client/http_client.dart';
import '../decoder.dart';
import '../error.dart';
import '../rest_request.dart';
import '../rest_response.dart';

/// Caches successful GET responses per URL and revalidates stale entries with
/// `If-None-Match` when the server provides an ETag.
class EtagCacheHttpClient implements HttpClient {
  /// Creates an ETag-aware cache wrapper.
  EtagCacheHttpClient({
    required this.inner,
    this.maxAge = const Duration(hours: 1),
  });

  final HttpClient inner;
  final Duration maxAge;
  final Map<String, ({RestResponse<dynamic> response, DateTime fetchedAt})>
      _entries =
      <String, ({RestResponse<dynamic> response, DateTime fetchedAt})>{};

  /// Removes every cached response.
  void clear() => _entries.clear();

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    if (request.method.toUpperCase() != 'GET') {
      return inner.execute(request, decoder: decoder, cancelToken: cancelToken);
    }

    final String key = request.fullUrl;
    final ({RestResponse<dynamic> response, DateTime fetchedAt})? entry =
        _entries[key];
    final DateTime now = DateTime.now();
    if (entry != null && now.difference(entry.fetchedAt) <= maxAge) {
      return _withRequest(entry.response, request);
    }

    final String? etag = _header(entry?.response.headers, 'etag');
    final RestRequest conditional = etag == null
        ? request
        : _copyRequest(request, <String, String>{'If-None-Match': etag});
    try {
      final RestResponse<dynamic> response = await inner.execute(
        conditional,
        decoder: decoder,
        cancelToken: cancelToken,
      );
      if (response.isSuccess) {
        _entries[key] = (response: response, fetchedAt: now);
      }
      return response;
    } on RestHttpException catch (error) {
      if (error.statusCode == 304 && entry != null) {
        return _withRequest(entry.response, request);
      }
      rethrow;
    }
  }

  @override
  Future<void> close() => inner.close();
}

String? _header(Map<String, String>? headers, String name) {
  if (headers == null) return null;
  for (final MapEntry<String, String> entry in headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  return null;
}

RestRequest _copyRequest(RestRequest request, Map<String, String> headers) {
  return RestRequest(
    method: request.method,
    path: request.path,
    baseUrl: request.baseUrl,
    headers: <String, String>{...request.headers, ...headers},
    body: request.body,
    queryParameters: request.queryParameters,
    pathParameters: request.pathParameters,
    timeout: request.timeout,
    cancelToken: request.cancelToken,
  );
}

RestResponse<dynamic> _withRequest(
  RestResponse<dynamic> response,
  RestRequest request,
) {
  return RestResponse<dynamic>(
    statusCode: response.statusCode,
    reasonPhrase: response.reasonPhrase,
    headers: response.headers,
    body: response.body,
    rawBody: response.rawBody,
    request: request,
  );
}
