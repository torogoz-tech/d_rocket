import 'package:d_rocket/d_rocket.dart';

/// Excepciones del runtime `d_rest` (ahora absorbed by `d_rocket`
/// under of the roadmap).
///
/// Hay tres tipos:
/// - [RestHttpException]: el servidor respondió con un status code no exitoso.
/// - [NetworkException]: falló la conexión (DNS, socket, timeout, etc.).
/// - [RestConfigException]: la configuración o las anotaciones son inválidas.
sealed class RestException implements Exception {
  const RestException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// El servidor respondió con un status code de error.
class RestHttpException extends RestException {
  RestHttpException({
    required this.statusCode,
    required this.request,
    this.reasonPhrase,
    this.rawBody = '',
    this.errorBody,
  }) : super('HTTP $statusCode${reasonPhrase != null ? ' $reasonPhrase' : ''}');

  final int statusCode;
  final String? reasonPhrase;
  final String rawBody;
  final Object? errorBody;
  final RestRequest request;

  /// Para `application/problem+json` estilo RFC 7807, si el servidor lo envía.
  Map<String, dynamic>? get problemDetails {
    final Object? body = errorBody;
    if (body is Map<String, dynamic>) return body;
    return null;
  }
}

/// Falló la conexión (sin respuesta del servidor).
class NetworkException extends RestException {
  NetworkException(super.message, {this.cause});
  final Object? cause;
}

/// Error de configuración (anotación faltante, baseUrl vacío, etc.).
class RestConfigException extends RestException {
  RestConfigException(super.message);
}
