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
          'url': request.fullUrl,
          if (DrocketDiagnostics.instance.includeSensitiveData &&
              request.headers.isNotEmpty)
            'headers': request.headers,
        },
      ),
    );
  }
}
