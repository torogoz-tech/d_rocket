/// Immutable response data shared by REST, SSE, and streaming policies.
class TransportResponseContext {
  const TransportResponseContext({
    required this.method,
    required this.uri,
    required this.statusCode,
    required this.headers,
    this.body,
    required this.attempt,
  });

  final String method;
  final Uri uri;
  final int statusCode;
  final Map<String, String> headers;
  final Object? body;
  final int attempt;
}
