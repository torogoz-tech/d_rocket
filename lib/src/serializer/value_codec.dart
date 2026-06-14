// .2e (split): the value codec subsystem.
// All codecs share the same shape (matches + encode)
// and live together as one cohesive "value codec"
// feature. The abstract [_ValueCodec] and all 9
// concrete implementations are kept in this single
// file because each codec is <20 lines and they
// share the same internal contract.
//
// This file is a `part of` [serializer.dart] because
// the private `_ValueCodec` types must live in the
// same library as [Serializer].

part of 'serializer.dart';

abstract class _ValueCodec {
  const _ValueCodec();
  bool matches(Object? value);
  Object? encode(Object? value, CodecEncoder encode);
}

class _NullAndPrimitivesCodec extends _ValueCodec {
  const _NullAndPrimitivesCodec();
  @override
  bool matches(Object? value) =>
      value == null || value is num || value is bool || value is String;
  @override
  Object? encode(Object? value, CodecEncoder encode) => value;
}

class _DateTimeCodec extends _ValueCodec {
  const _DateTimeCodec();
  @override
  bool matches(Object? value) => value is DateTime;
  @override
  Object? encode(Object? value, CodecEncoder encode) =>
      (value! as DateTime).toIso8601String();
}

class _UriCodec extends _ValueCodec {
  const _UriCodec();
  @override
  bool matches(Object? value) => value is Uri;
  @override
  Object? encode(Object? value, CodecEncoder encode) =>
      (value! as Uri).toString();
}

class _BigIntCodec extends _ValueCodec {
  const _BigIntCodec();
  @override
  bool matches(Object? value) => value is BigInt;
  @override
  Object? encode(Object? value, CodecEncoder encode) =>
      (value! as BigInt).toString();
}

class _DurationCodec extends _ValueCodec {
  const _DurationCodec();
  @override
  bool matches(Object? value) => value is Duration;
  @override
  Object? encode(Object? value, CodecEncoder encode) =>
      (value! as Duration).inMicroseconds;
}

class _EnumCodec extends _ValueCodec {
  const _EnumCodec();
  @override
  bool matches(Object? value) => value is Enum;
  @override
  Object? encode(Object? value, CodecEncoder encode) => (value! as Enum).name;
}

class _ListCodec extends _ValueCodec {
  const _ListCodec();
  @override
  bool matches(Object? value) => value is List;
  @override
  Object? encode(Object? value, CodecEncoder encode) =>
      (value! as List).map(encode).toList();
}

class _SetCodec extends _ValueCodec {
  const _SetCodec();
  @override
  bool matches(Object? value) => value is Set;
  @override
  Object? encode(Object? value, CodecEncoder encode) {
    return (value! as Set).map(encode).toList();
  }
}

class _MapCodec extends _ValueCodec {
  const _MapCodec();
  @override
  bool matches(Object? value) => value is Map;
  @override
  Object? encode(Object? value, CodecEncoder encode) {
    final Map<dynamic, dynamic> map = value! as Map<dynamic, dynamic>;
    validateMapKeysImpl(map);
    return map.map(
      (dynamic key, dynamic item) => MapEntry(key.toString(), encode(item)),
    );
  }
}

void validateMapKeysImpl(Map<dynamic, dynamic> map) {
  for (final dynamic key in map.keys) {
    if (key == null) {
      throw ArgumentError(
        'Map keys must not be null when serialising to JSON.',
      );
    }
    if (key is String || key is num || key is bool) continue;
    if (key is! DateTime && key is! Uri && key is! BigInt && key is! Enum) {
      continue;
    }
  }
}
