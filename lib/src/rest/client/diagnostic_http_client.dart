import 'package:d_rocket/d_rocket.dart';

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
        statusCode: response?.statusCode,
        error: error?.toString(),
        metadata: <String, Object?>{
          'request': _requestPayload(request, diagnostics),
          'response': _responsePayload(response, diagnostics),
        },
      ),
    );
  }

  Map<String, Object?> _requestPayload(
    RestRequest request,
    DrocketDiagnostics diagnostics,
  ) {
    final String body = request.bodyAsString;
    return <String, Object?>{
      'method': request.method,
      'url': request.fullUrl,
      'headers': diagnostics.includeSensitiveData
          ? request.headers
          : request.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? body : '<hidden>',
      'bodyLength': body.length,
    };
  }

  Map<String, Object?> _responsePayload(
    RestResponse<dynamic>? response,
    DrocketDiagnostics diagnostics,
  ) {
    if (response == null) return const <String, Object?>{};
    return <String, Object?>{
      'statusCode': response.statusCode,
      if (response.reasonPhrase != null) 'reasonPhrase': response.reasonPhrase,
      'headers': diagnostics.includeSensitiveData
          ? response.headers
          : response.headers.keys.toList(growable: false),
      'body': diagnostics.includeSensitiveData ? response.rawBody : '<hidden>',
      'bodyLength': response.rawBody.length,
    };
  }
}
