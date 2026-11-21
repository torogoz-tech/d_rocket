/// Immutable request data shared by REST, SSE, and streaming policies.
class TransportRequestContext {
  const TransportRequestContext({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
    required this.attempt,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final Object? body;
  final int attempt;

  TransportRequestContext copyWith({
    String? method,
    Uri? uri,
    Map<String, String>? headers,
    Object? body,
    int? attempt,
  }) {
    return TransportRequestContext(
      method: method ?? this.method,
      uri: uri ?? this.uri,
      headers: Map<String, String>.unmodifiable(headers ?? this.headers),
      body: body ?? this.body,
      attempt: attempt ?? this.attempt,
    );
  }

  /// Creates a redirected request and strips credentials when its origin
  /// differs from the original request.
  TransportRequestContext forRedirect(Uri redirectedUri) {
    final bool sameOrigin = uri.scheme == redirectedUri.scheme &&
        uri.host == redirectedUri.host &&
        uri.port == redirectedUri.port;
    if (sameOrigin) return copyWith(uri: redirectedUri);

    final Map<String, String> safeHeaders = <String, String>{};
    for (final MapEntry<String, String> entry in headers.entries) {
      if (_credentialHeaders.contains(entry.key.toLowerCase())) continue;
      safeHeaders[entry.key] = entry.value;
    }
    return copyWith(uri: redirectedUri, headers: safeHeaders);
  }

  static const Set<String> _credentialHeaders = <String>{
    'authorization',
    'dpop',
    'cookie',
    'proxy-authorization',
    'set-cookie',
  };
}
