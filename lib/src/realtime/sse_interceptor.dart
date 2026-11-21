import 'package:http/http.dart' as http;

/// Allows [HttpSseClient] to customize an SSE request lifecycle.
abstract class SseInterceptor {
  /// Called after the default and connection headers are assembled.
  Future<http.BaseRequest> onRequest(http.BaseRequest request) async => request;

  /// Called after the initial HTTP response is received.
  Future<http.StreamedResponse> onResponse(
    http.StreamedResponse response,
  ) async =>
      response;

  /// Called when opening or consuming the connection fails.
  Future<void> onError(Object error, StackTrace stackTrace) async {}
}

/// Applies SSE interceptors in registration order.
class CompositeSseInterceptor extends SseInterceptor {
  CompositeSseInterceptor(this.interceptors);

  final List<SseInterceptor> interceptors;

  @override
  Future<http.BaseRequest> onRequest(http.BaseRequest request) async {
    http.BaseRequest current = request;
    for (final SseInterceptor interceptor in interceptors) {
      current = await interceptor.onRequest(current);
    }
    return current;
  }

  @override
  Future<http.StreamedResponse> onResponse(
    http.StreamedResponse response,
  ) async {
    http.StreamedResponse current = response;
    for (final SseInterceptor interceptor in interceptors) {
      current = await interceptor.onResponse(current);
    }
    return current;
  }

  @override
  Future<void> onError(Object error, StackTrace stackTrace) async {
    for (final SseInterceptor interceptor in interceptors) {
      await interceptor.onError(error, stackTrace);
    }
  }
}
