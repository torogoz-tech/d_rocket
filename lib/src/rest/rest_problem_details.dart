/// Typed view of an RFC 7807-style REST error payload.
class RestProblemDetails {
  const RestProblemDetails({
    this.type,
    this.title,
    this.status,
    this.detail,
    this.instance,
    this.code,
    this.traceId,
    this.requestId,
    this.extensions = const <String, Object?>{},
  });

  /// Creates a typed view when [body] is a JSON object.
  factory RestProblemDetails.fromJson(Object? body) {
    if (body is! Map) return const RestProblemDetails();
    final Map<String, Object?> values = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in body.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    final Object? status = values['status'];
    final Map<String, Object?> extensions = Map<String, Object?>.from(values)
      ..removeWhere(
        (String key, Object? value) => <String>{
          'type',
          'title',
          'status',
          'detail',
          'instance'
        }.contains(key),
      );
    return RestProblemDetails(
      type: _asString(values['type']),
      title: _asString(values['title']),
      status: status is int ? status : int.tryParse('$status'),
      detail: _asString(values['detail']),
      instance: _asString(values['instance']),
      code: _asString(values['code'] ?? values['errorCode']),
      traceId: _asString(values['traceId'] ?? values['trace_id']),
      requestId: _asString(values['requestId'] ?? values['request_id']),
      extensions: extensions,
    );
  }

  final String? type;
  final String? title;
  final int? status;
  final String? detail;
  final String? instance;
  final String? code;
  final String? traceId;
  final String? requestId;
  final Map<String, Object?> extensions;

  /// Validation messages keyed by field when the payload contains `errors`.
  Map<String, List<String>> get validationErrors {
    final Object? value = extensions['errors'];
    if (value is! Map) return const <String, List<String>>{};
    return <String, List<String>>{
      for (final MapEntry<Object?, Object?> entry in value.entries)
        if (entry.key is String) entry.key! as String: _asMessages(entry.value),
    };
  }

  List<String> _asMessages(Object? value) {
    if (value is Iterable) return value.map((Object? item) => '$item').toList();
    return value == null ? const <String>[] : <String>['$value'];
  }

  static String? _asString(Object? value) => value is String ? value : null;
}
