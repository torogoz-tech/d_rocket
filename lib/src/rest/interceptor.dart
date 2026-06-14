import 'package:d_rocket/d_rocket.dart';

/// Interceptor estilo Refit/OkHttp. Permite transformar peticiones
/// (p. ej. añadir `Authorization`) y respuestas (p. ej. refrescar
/// tokens en 401).
abstract class RestInterceptor {
  /// Se llama antes de enviar la petición. Devuelve la petición
  /// (posiblemente modificada) o lanza una [RestException] para
  /// abortar.
  Future<RestRequest> onRequest(RestRequest request) async => request;

  /// Se llama después de recibir la respuesta (incluso para errores).
  Future<RestResponse<dynamic>> onResponse(
          RestResponse<dynamic> response) async =>
      response;

  /// Se llama si la petición falla por red o por status code.
  Future<RestException> onError(RestException error) async => error;
}

/// Composición de varios interceptores en orden.
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
