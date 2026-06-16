import 'package:d_rocket/d_rocket.dart';

/// Refit/OkHttp-style interceptor. Lets you transform
/// requests (e.g. add an `Authorization` header) and
/// responses (e.g. refresh a token on 401).
abstract class RestInterceptor {
  /// Called before the request is sent. Returns the
  /// (possibly modified) request, or throws a
  /// [RestException] to abort the call.
  Future<RestRequest> onRequest(RestRequest request) async => request;

  /// Called after the response is received (including
  /// error responses).
  Future<RestResponse<dynamic>> onResponse(
          RestResponse<dynamic> response) async =>
      response;

  /// Called when the request fails (network error or
  /// non-success status code).
  Future<RestException> onError(RestException error) async => error;
}

/// Composes several interceptors in order.
class CompositeInterceptor implements RestInterceptor {
  final List<RestInterceptor> interceptors;
  CompositeInterceptor(this.interceptors);

  @override
  Future<RestRequest> onRequest(RestRequest request) async {
    RestRequest current = request;
    for (final RestInterceptor i in interceptors) {
      current = await i.onRequest(current);
    }
    return current;
  }

  @override
  Future<RestResponse<dynamic>> onResponse(
      RestResponse<dynamic> response) async {
    RestResponse<dynamic> current = response;
    for (final RestInterceptor i in interceptors) {
      current = await i.onResponse(current);
    }
    return current;
  }

  @override
  Future<RestException> onError(RestException error) async {
    RestException current = error;
    for (final RestInterceptor i in interceptors) {
      current = await i.onError(current);
    }
    return current;
  }
}
