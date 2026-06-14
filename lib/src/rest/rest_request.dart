// .x (absorbed from d_rest): `RestRequest`
// represents an outgoing HTTP request. The codegen
// produces instances of this class from the
// annotations and the method arguments.
//
// Private helpers (`_resolvePlaceholders`,
// `_joinUrl`) live in this file because they are
// implementation details of [RestRequest.fullUrl].

import 'dart:convert';

import 'cancel_token.dart';

class RestRequest {
  /// HTTP verb (`GET`, `POST`, etc.).
  final String method;

  /// Relative path (no baseUrl), e.g. `/api/v1/todos/{id}`.
  final String path;

  /// Final base URL (resolved in codegen from
  /// `@RestClient.baseUrl` + `@Route`).
  final String baseUrl;

  /// Final headers (class + method + parameter combined).
  final Map<String, String> headers;

  /// Serialised body. May be:
  /// - `String` (JSON or raw)
  /// - `List<int>` (binary)
  /// - `null` for verbs without a body
  final Object? body;

  /// Explicit query string (may already be in [path]).
  final Map<String, String> queryParameters;

  /// Resolved path params (key -> value). Used for
  /// tracing / logging only.
  final Map<String, Object> pathParameters;

  /// Optional per-call timeout.
  final Duration? timeout;

  /// (new): optional cancellation
  /// token. The user passes a [CancelToken] when
  /// calling [HttpClient.execute]; if the token is
  /// cancelled mid-flight, the HTTP call aborts
  /// the socket and surfaces a
  /// [RequestCancelledException]. `null` means
  /// "this request cannot be cancelled" (the
  /// legacy behaviour).
  final CancelToken? cancelToken;

  const RestRequest({
    required this.method,
    required this.path,
    this.baseUrl = '',
    this.headers = const <String, String>{},
    this.body,
    this.queryParameters = const <String, String>{},
    this.pathParameters = const <String, Object>{},
    this.timeout,
    this.cancelToken,
  });

  /// Full URL resolving `{name}` placeholders with
  /// [pathParameters].
  String get fullUrl {
    final String resolvedPath = _resolvePlaceholders(path, pathParameters);
    final String full = _joinUrl(baseUrl, resolvedPath);
    if (queryParameters.isEmpty) return full;
    final Uri uri = Uri.parse(full);
    return uri.replace(
      queryParameters: <String, String>{
        ...uri.queryParameters,
        ...queryParameters,
      },
    ).toString();
  }

  /// Body as text (UTF-8). Returns `''` if no body.
  String get bodyAsString {
    if (body == null) return '';
    if (body is String) return body! as String;
    if (body is List<int>) return utf8.decode(body! as List<int>);
    return body.toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'method': method,
        'url': fullUrl,
        'headers': headers,
        'body': bodyAsString,
        if (cancelToken != null) 'cancellable': true,
      };

  @override
  String toString() => 'RestRequest(${toJson()})';
}

String _resolvePlaceholders(String template, Map<String, Object> values) {
  return template.replaceAllMapped(
    RegExp(r'\{([a-zA-Z_][\w]*)\}'),
    (Match m) {
      final String? name = m.group(1);
      if (name == null) {
        throw StateError('Invalid placeholder in path "$template".');
      }
      final Object? value = values[name];
      if (value == null) {
        throw StateError(
          'Missing path parameter "$name" for path "$template".',
        );
      }
      return Uri.encodeComponent(value.toString());
    },
  );
}

String _joinUrl(String base, String path) {
  if (base.isEmpty) return path;
  if (path.isEmpty) return base;
  final bool baseEnds = base.endsWith('/');
  final bool pathStarts = path.startsWith('/');
  if (baseEnds && pathStarts) return '$base${path.substring(1)}';
  if (!baseEnds && !pathStarts) return '$base/$path';
  return '$base$path';
}
