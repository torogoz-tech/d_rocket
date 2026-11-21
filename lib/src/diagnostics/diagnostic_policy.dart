import 'dart:convert';

/// Configures values that must be hidden from development diagnostics.
class DiagnosticPolicy {
  const DiagnosticPolicy({
    this.sensitiveHeaders = const <String>{
      'Authorization',
      'DPoP',
      'Cookie',
      'Set-Cookie',
      'Proxy-Authorization',
      'X-Api-Key',
    },
    this.sensitiveBodyFields = const <String>{
      'cardNumber',
      'cvv',
      'access_token',
      'refresh_token',
    },
    this.redactedValue = '<redacted>',
  });

  final Set<String> sensitiveHeaders;
  final Set<String> sensitiveBodyFields;
  final String redactedValue;

  Map<String, String> redactHeaders(Map<String, String> headers) {
    return headers.map(
      (String key, String value) => MapEntry<String, String>(
        key,
        _containsIgnoreCase(sensitiveHeaders, key) ? redactedValue : value,
      ),
    );
  }

  String redactBodyText(String body) {
    if (body.isEmpty) return body;
    try {
      final Object? decoded = jsonDecode(body);
      if (!_containsSensitiveField(decoded)) return body;
      return jsonEncode(redactJson(decoded));
    } on FormatException {
      return body;
    }
  }

  Object? redactJson(Object? value) {
    if (value is List<Object?>) {
      return value.map<Object?>(redactJson).toList(growable: false);
    }
    if (value is Map<Object?, Object?>) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> entry in value.entries)
          entry.key.toString(): _isSensitiveField(entry.key.toString())
              ? redactedValue
              : redactJson(entry.value),
      };
    }
    return value;
  }

  bool _containsSensitiveField(Object? value) {
    if (value is List<Object?>) return value.any(_containsSensitiveField);
    if (value is Map<Object?, Object?>) {
      for (final MapEntry<Object?, Object?> entry in value.entries) {
        if (_isSensitiveField(entry.key.toString()) ||
            _containsSensitiveField(entry.value)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isSensitiveField(String key) =>
      _containsIgnoreCase(sensitiveBodyFields, key);

  bool _containsIgnoreCase(Iterable<String> values, String candidate) {
    final String lowerCandidate = candidate.toLowerCase();
    return values.any((String value) => value.toLowerCase() == lowerCandidate);
  }
}
