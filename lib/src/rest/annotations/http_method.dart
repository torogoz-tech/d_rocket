/// Verbo HTTP. Cada subclase se mapea a un `HttpMethod` específico.
///
/// ```dart
/// @HttpGet // GET /resource
/// @HttpGet('/{id}') // GET /resource/{id}
/// @HttpPost // POST /resource
/// @HttpPut('/{id}') // PUT /resource/{id}
/// @HttpPatch('/{id}') // PATCH /resource/{id}
/// @HttpDelete('/{id}') // DELETE /resource/{id}
/// ```
sealed class HttpVerb {
  final String path;

  /// Headers extra para este método (se combinan con los de clase).
  final Map<String, String> headers;

  const HttpVerb(this.path, [this.headers = const <String, String>{}]);
}

class HttpGet extends HttpVerb {
  const HttpGet([super.path = '', super.headers = const <String, String>{}]);
}

class HttpPost extends HttpVerb {
  const HttpPost([super.path = '', super.headers = const <String, String>{}]);
}

class HttpPut extends HttpVerb {
  const HttpPut([super.path = '', super.headers = const <String, String>{}]);
}

class HttpPatch extends HttpVerb {
  const HttpPatch([super.path = '', super.headers = const <String, String>{}]);
}

class HttpDelete extends HttpVerb {
  const HttpDelete([super.path = '', super.headers = const <String, String>{}]);
}

class HttpHead extends HttpVerb {
  const HttpHead([super.path = '', super.headers = const <String, String>{}]);
}

class HttpOptions extends HttpVerb {
  const HttpOptions(
      [super.path = '', super.headers = const <String, String>{}]);
}

/// Atajo para serializar verbos en strings.
String httpVerbToString(HttpVerb verb) {
  if (verb is HttpGet) return 'GET';
  if (verb is HttpPost) return 'POST';
  if (verb is HttpPut) return 'PUT';
  if (verb is HttpPatch) return 'PATCH';
  if (verb is HttpDelete) return 'DELETE';
  if (verb is HttpHead) return 'HEAD';
  if (verb is HttpOptions) return 'OPTIONS';
  throw ArgumentError('Unknown HttpVerb: $verb');
}
