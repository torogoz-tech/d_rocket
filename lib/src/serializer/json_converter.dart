/// Converts one declared Dart type to and from a JSON-compatible value.
class JsonConverter<T, R> {
  const JsonConverter({required this.fromJson, required this.toJson});

  final T Function(R value) fromJson;
  final R Function(T value) toJson;

  T decode(Object? value) => fromJson(value as R);
  Object? encode(T value) => toJson(value);
}
