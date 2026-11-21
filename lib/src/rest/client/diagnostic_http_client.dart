import 'package:d_rocket/d_rocket.dart';

import 'diagnostic_payload.dart';

/// HTTP wrapper that publishes one structured event per request.
class DiagnosticHttpClient implements HttpClient {
  const DiagnosticHttpClient(this.inner, {this.policy});

  final HttpClient inner;
  final DiagnosticPolicy? policy;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    final DateTime started = DateTime.now();
    final DrocketDiagnostics diagnostics = DrocketDiagnostics.instance;
    final DiagnosticPolicy activePolicy =
        policy ?? diagnostics.diagnosticPolicy;
    try {
      final response = await inner.execute(
        request,
        decoder: decoder,
        cancelToken: cancelToken,
      );
      _record(request, started, response: response, policy: activePolicy);
      return response;
    } catch (error) {
      _record(request, started, error: error, policy: activePolicy);
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
    required DiagnosticPolicy policy,
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
          'request': _requestPayload(request, diagnostics, policy),
          'response': response != null
              ? _responsePayload(response, diagnostics, policy)
              : _errorResponsePayload(error, diagnostics, policy),
        },
      ),
    );
  }

  Map<String, Object?> _requestPayload(
    RestRequest request,
    DrocketDiagnostics diagnostics,
    DiagnosticPolicy policy,
  ) {
    final String body = request.bodyAsString;
    final payload = _boundedPayload(
      policy.redactBodyText(body),
      diagnostics.maxPayloadLength,
    );
    return <String, Object?>{
      'method': request.method,
      'url': request.fullUrl,
      'headers': diagnostics.includeSensitiveData
          ? policy.redactHeaders(request.headers)
          : request.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? payload.value : '<hidden>',
      'bodyLength': body.length,
      if (payload.truncated) 'bodyTruncated': true,
    };
  }

  Map<String, Object?> _responsePayload(
    RestResponse<dynamic>? response,
    DrocketDiagnostics diagnostics,
    DiagnosticPolicy policy,
  ) {
    if (response == null) return const <String, Object?>{};
    final payload = _boundedPayload(
      policy.redactBodyText(response.rawBody),
      diagnostics.maxPayloadLength,
    );
    return <String, Object?>{
      'statusCode': response.statusCode,
      if (response.reasonPhrase != null) 'reasonPhrase': response.reasonPhrase,
      'headers': diagnostics.includeSensitiveData
          ? policy.redactHeaders(response.headers)
          : response.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? payload.value : '<hidden>',
      'bodyLength': response.rawBody.length,
      if (payload.truncated) 'bodyTruncated': true,
    };
  }

  Map<String, Object?> _errorResponsePayload(
    Object? error,
    DrocketDiagnostics diagnostics,
    DiagnosticPolicy policy,
  ) {
    if (error is! RestHttpException) return const <String, Object?>{};
    final payload = _boundedPayload(
      policy.redactBodyText(error.rawBody),
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
}
