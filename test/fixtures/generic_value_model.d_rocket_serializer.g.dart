// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'generic_value_model.dart';

// **************************************************************************
// SerializableGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: non_constant_identifier_names

GenericValue<T> GenericValueFromJson<T>(
    Map<String, dynamic> json, T Function(Object?) decodeT) {
  return GenericValue(
    data: Serializer.decodeField<T?>(
        field: 'GenericValue.data',
        raw: json['data'],
        decode: () => json['data'] == null ? null : decodeT(json['data'])),
    message: Serializer.decodeField<String?>(
        field: 'GenericValue.message',
        raw: json['message'],
        decode: () => json['message'] as String?),
  );
}

Map<String, dynamic> GenericValueToJson<T>(
    GenericValue<T> value, Object? Function(T) encodeT) {
  return <String, dynamic>{
    'data': value.data == null ? null : encodeT(value.data as T),
    'message': value.message,
  };
}

/// Registers encoders/decoders for [GenericValue]. You must
/// provide a `decode[T]` and `encode[T]` for every type parameter.
/// The callbacks receive or return raw JSON values, so they can represent
/// objects, lists, maps and scalar values.
/// that this class uses, and call this for every concrete
/// instantiation:
///
/// ```dart
/// registerApiResponseSerializer[User](
///   decode: UserFromJson,
///   encode: UserToJson,
/// );
/// ```
void registerGenericValueSerializer<T>({
  required T Function(Object?) decode,
  required Object? Function(T) encode,
}) {
  Serializer.register<GenericValue<T>>(
    fromJson: (Map<String, dynamic> json) =>
        GenericValueFromJson<T>(json, decode),
    toJson: (GenericValue<T> value) => GenericValueToJson<T>(value, encode),
  );
}
// Generic classes do not get a `toJson()` extension; use the
// static `GenericValueToJson<T>(value, encodeT: ...)` function.

const Object _$GenericValueCopyWithSentinel = Object();

extension GenericValueCopyWith<T> on GenericValue<T> {
  GenericValue<T> copyWith({
    Object? data = _$GenericValueCopyWithSentinel,
    Object? message = _$GenericValueCopyWithSentinel,
  }) {
    return GenericValue<T>(
      data: identical(data, _$GenericValueCopyWithSentinel)
          ? this.data
          : data as T?,
      message: identical(message, _$GenericValueCopyWithSentinel)
          ? this.message
          : message as String?,
    );
  }
}

mixin _$GenericValueEquality<T> {
  @override
  bool operator ==(Object other) {
    final GenericValue<T> self = this as GenericValue<T>;
    return identical(this, other) ||
        other is GenericValue<T> &&
            ValueEquality.equals(self.data, (other as GenericValue<T>).data) &&
            ValueEquality.equals(
                self.message, (other as GenericValue<T>).message);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
        ValueEquality.hash((this as GenericValue<T>).data),
        ValueEquality.hash((this as GenericValue<T>).message),
      ]);
}

Map<String, Object?> GenericValueJsonSchema() {
  return <String, Object?>{
    '\$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'GenericValue',
    'type': 'object',
    'properties': <String, Object?>{
      'data': <String, Object?>{'type': 'object'},
      'message': <String, Object?>{'type': 'string'},
    },
    'required': <String>[],
  };
}
