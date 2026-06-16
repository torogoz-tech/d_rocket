import 'package:d_rocket/d_rocket.dart';

/// Exceptions raised by the d_rest runtime (now
/// absorbed into d_rocket as part of the roadmap).
///
/// Three flavors:
/// - [RestHttpException]: the server responded with a
///   non-success status code.
/// - [NetworkException]: the connection failed (DNS,
///   socket, timeout, etc.).
/// - [RestConfigException]: the configuration or the
///   annotations are invalid.
sealed class RestException implements Exception {
  const RestException(this.message);
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The server responded with an error status code.
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

  /// For `application/problem+json` (RFC 7807), if the
  /// server sent it.
  Map<String, dynamic>? get problemDetails {
    final Object? body = errorBody;
    if (body is Map<String, dynamic>) return body;
    return null;
  }
}

/// The connection failed (no response from the server).
class NetworkException extends RestException {
  NetworkException(super.message, {this.cause});
  final Object? cause;
}

/// Configuration error (missing annotation, empty baseUrl, etc.).
class RestConfigException extends RestException {
  RestConfigException(super.message);
}
