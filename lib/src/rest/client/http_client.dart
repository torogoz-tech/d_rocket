import 'package:d_rocket/d_rocket.dart';

/// Interfaz abstracta que todo backend HTTP debe implementar.
///
/// `d_rocket` (capa 2 — REST with steroids) trae una implementación
/// por defecto sobre `package:http` ([HttpPackageClient]), pero se
/// puede cambiar fácilmente:
/// ```dart
/// dRest.client = MyDioRestClient;
/// ```
abstract class HttpClient {
  /// Ejecuta la petición y devuelve una respuesta "cruda" (todavía
  /// sin decodificar el body a un tipo concreto). El [RestClient]
  /// se encarga de aplicar el [Decoder].
  ///
  /// (new): accepts an optional
  /// [CancelToken]. When the token is cancelled
  /// mid-flight, the implementation must abort the
  /// in-flight socket and the returned [Future]
  /// fails with a [RequestCancelledException]
  /// (carrying the reason from `token.cancel(...)`).
  /// Implementations that cannot honour the token
  /// must still complete the call (cancellation
  /// is best-effort).
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  });

  /// Permite liberar recursos. Por defecto es no-op.
  Future<void> close() async {}
}
