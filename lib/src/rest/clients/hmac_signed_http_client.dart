import 'dart:convert';

import '../cancel_token.dart';
import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';
import 'hmac_http_client.dart';

/// Adds an HMAC signature and timestamp header to every outgoing request.
class HmacSignedHttpClient implements HttpClient {
  /// Creates an HMAC signing wrapper.
  HmacSignedHttpClient({
    required this.inner,
    required this.signer,
    this.signatureHeader = 'X-Signature',
    this.timestampHeader = 'X-Signature-Timestamp',
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  final HttpClient inner;
  final HmacSha256Signer signer;
  final String signatureHeader;
  final String timestampHeader;
  final DateTime Function() clock;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) {
    final String timestamp = clock().toUtc().toIso8601String();
    final String signature = signer.signRequest(
      method: request.method,
      url: request.fullUrl,
      body: utf8.encode(request.bodyAsString),
      timestamp: timestamp,
    );
    final RestRequest signed = RestRequest(
      method: request.method,
      path: request.path,
      baseUrl: request.baseUrl,
      headers: <String, String>{
        ...request.headers,
        signatureHeader: signature,
        timestampHeader: timestamp,
      },
      body: request.body,
      queryParameters: request.queryParameters,
      pathParameters: request.pathParameters,
      timeout: request.timeout,
      cancelToken: request.cancelToken,
    );
    return inner.execute(signed, decoder: decoder, cancelToken: cancelToken);
  }

  @override
  Future<void> close() => inner.close();
}
