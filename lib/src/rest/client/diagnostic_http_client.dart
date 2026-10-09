import 'package:d_rocket/d_rocket.dart';

import 'diagnostic_payload.dart';

/// HTTP wrapper that publishes one structured event per request.
class DiagnosticHttpClient implements HttpClient {
  const DiagnosticHttpClient(this.inner);

  final HttpClient inner;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    final DateTime started = DateTime.now();
    try {
      final response = await inner.execute(
        request,
        decoder: decoder,
        cancelToken: cancelToken,
      );
      _record(request, started, response: response);
      return response;
    } catch (error) {
      _record(request, started, error: error);
      rethrow;
    }
  }

  @override
  Future<void> close() => inner.close();

  void _record(
    RestRequest request,
    DateTime started, {
    RestResponse<dynamic>? response,
    Object? error,
  }) {
    final diagnostics = DrocketDiagnostics.instance;
    DrocketDiagnostics.instance.record(
      DiagnosticEvent(
        category: DiagnosticCategory.rest,
        operation: request.method,
        startedAt: started,
        duration: DateTime.now().difference(started),
        success: error == null && response?.isSuccess == true,
        statusCode: response?.statusCode ??
            (error is RestHttpException ? error.statusCode : null),
        error: error?.toString(),
        metadata: <String, Object?>{
          'request': _requestPayload(request, diagnostics),
          'response': response != null
              ? _responsePayload(response, diagnostics)
              : _errorResponsePayload(error, diagnostics),
        },
      ),
    );
  }

  Map<String, Object?> _requestPayload(
    RestRequest request,
    DrocketDiagnostics diagnostics,
  ) {
    final String body = request.bodyAsString;
    final payload = _boundedPayload(body, diagnostics.maxPayloadLength);
    return <String, Object?>{
      'method': request.method,
      'url': request.fullUrl,
      'headers': diagnostics.includeSensitiveData
          ? _redactHeaders(request.headers)
          : request.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? payload.value : '<hidden>',
      'bodyLength': body.length,
      if (payload.truncated) 'bodyTruncated': true,
    };
  }

  Map<String, Object?> _responsePayload(
    RestResponse<dynamic>? response,
    DrocketDiagnostics diagnostics,
  ) {
    if (response == null) return const <String, Object?>{};
    final payload = _boundedPayload(
      response.rawBody,
      diagnostics.maxPayloadLength,
    );
    return <String, Object?>{
      'statusCode': response.statusCode,
      if (response.reasonPhrase != null) 'reasonPhrase': response.reasonPhrase,
      'headers': diagnostics.includeSensitiveData
          ? _redactHeaders(response.headers)
          : response.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? payload.value : '<hidden>',
      'bodyLength': response.rawBody.length,
      if (payload.truncated) 'bodyTruncated': true,
    };
  }

  Map<String, Object?> _errorResponsePayload(
    Object? error,
    DrocketDiagnostics diagnostics,
  ) {
    if (error is! RestHttpException) return const <String, Object?>{};
    final payload = _boundedPayload(
      error.rawBody,
      diagnostics.maxPayloadLength,
    );
    return <String, Object?>{
      'statusCode': error.statusCode,
      if (error.reasonPhrase != null) 'reasonPhrase': error.reasonPhrase,
      'body': diagnostics.includeSensitiveData ? payload.value : '<hidden>',
      'bodyLength': error.rawBody.length,
      if (payload.truncated) 'bodyTruncated': true,
    };
  }

  DiagnosticPayload _boundedPayload(String value, int maxLength) {
    if (value.length <= maxLength) {
      return DiagnosticPayload(value: value, truncated: false);
    }
    return DiagnosticPayload(
      value: value.substring(0, maxLength),
      truncated: true,
    );
  }

  Map<String, String> _redactHeaders(Map<String, String> headers) {
    return headers.map(
      (key, value) => MapEntry(
        key,
        _sensitiveHeaderNames.contains(key.toLowerCase())
            ? '<redacted>'
            : value,
      ),
    );
  }

  static const Set<String> _sensitiveHeaderNames = <String>{
    'authorization',
    'cookie',
    'set-cookie',
    'proxy-authorization',
    'x-api-key',
  };
}
