// + .2e (split): `Serializer` is
// the public runtime. The value codec subsystem
// (abstract + 9 concrete implementations + the
// validateMapKeysImpl helper) lives in
// [value_codec.dart] as a `part of` this file
// because the private `_ValueCodec` types must
// be in the same library as [Serializer].
//
// The 3 public typedefs (`JsonFactory`,
// `JsonEncoder`, `CodecEncoder`) and the
// [SerializerSnapshot] class each have their own
// file.

import 'dart:convert';

import 'codec_encoder.dart';
import 'json_encoder.dart';
import 'json_factory.dart';

export 'codec_encoder.dart';
export 'json_encoder.dart';
export 'json_factory.dart';

part 'serializer_snapshot.dart';
part 'value_codec.dart';

/// Static JSON serializer with type registration.
///
/// The registry state is held in process-wide static
/// maps, which makes [Serializer] thread-unsafe
/// across isolates. For server-side use cases that
/// need isolation, create your own subclass or wrap
/// the registration calls in your own mutex. For
/// typical Flutter / CLI use (single isolate) the
/// current implementation is sufficient.
///
/// Use [Serializer.reset] between tests to clear the
/// registry and [Serializer.snapshot] to introspect
/// it for debugging.
class Serializer {
  static final Map<Type, JsonFactory<dynamic>> _factories =
      <Type, JsonFactory<dynamic>>{};
  static final Map<Type, JsonEncoder<dynamic>> _encoders =
      <Type, JsonEncoder<dynamic>>{};
  static final Map<Type, String> _unionTypeFields = <Type, String>{};
  static final Map<Type, Map<String, JsonFactory<dynamic>>> _unionFactories =
      <Type, Map<String, JsonFactory<dynamic>>>{};

  /// Built-in value codecs, tried in order.
  static const List<_ValueCodec> _valueCodecs = <_ValueCodec>[
    _NullAndPrimitivesCodec(),
    _DateTimeCodec(),
    _UriCodec(),
    _BigIntCodec(),
    _DurationCodec(),
    _EnumCodec(),
    _ListCodec(),
    _SetCodec(),
    _MapCodec(),
  ];

  /// Registers conversion functions for a specific
  /// type.
  static void register<T>({
    required JsonFactory<T> fromJson,
    required JsonEncoder<T> toJson,
  }) {
    _factories[T] = (Map<String, dynamic> json) => fromJson(json);
    _encoders[T] = (dynamic value) => toJson(value as T);
  }

  /// Registers a union subtype factory under a
  /// discriminator value.
  static void registerUnion<T>({
    required String typeField,
    required String discriminator,
    required JsonFactory<T> fromJson,
  }) {
    final String? existingTypeField = _unionTypeFields[T];
    if (existingTypeField != null && existingTypeField != typeField) {
      throw StateError(
        'Union type field mismatch for $T: '
        'existing "$existingTypeField", incoming "$typeField".',
      );
    }

    _unionTypeFields[T] = typeField;
    final Map<String, JsonFactory<dynamic>> unions =
        _unionFactories.putIfAbsent(T, () => <String, JsonFactory<dynamic>>{});
    unions[discriminator] = (Map<String, dynamic> json) => fromJson(json);
  }

  /// Serializes [value] to JSON text.
  static String toJson<T>(T value) {
    final Object? payload = _encodeValue(value);
    return jsonEncode(payload);
  }

  /// Deserializes JSON text into type [T].
  static T fromJson<T>(String json) {
    final dynamic decoded = jsonDecode(json);
    return fromDynamic<T>(decoded);
  }

  /// Deserializes a decoded JSON value into type [T].
  static T fromDynamic<T>(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      return _decodeMap<T>(decoded);
    }

    if (decoded == null ||
        decoded is num ||
        decoded is bool ||
        decoded is String) {
      return decoded as T;
    }

    throw ArgumentError('Unsupported JSON payload for type $T');
  }

  /// Encodes a runtime value to a JSON-compatible
  /// structure.
  static Object? encodeDynamic(Object? value) => _encodeValue(value);

  /// Formats a [DateTime] with a supported [pattern].
  static String formatDate(DateTime value, String pattern) {
    if (pattern == 'yyyy-MM-dd') {
      final String year = value.year.toString().padLeft(4, '0');
      final String month = value.month.toString().padLeft(2, '0');
      final String day = value.day.toString().padLeft(2, '0');
      return '$year-$month-$day';
    }

    if (pattern == 'iso8601') {
      return value.toIso8601String();
    }

    throw UnsupportedError('Unsupported date format pattern: $pattern');
  }

  /// Parses a [DateTime] using a supported [pattern].
  static DateTime parseDate(String value, String pattern) {
    if (pattern == 'yyyy-MM-dd') {
      final RegExp regExp = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
      final RegExpMatch? match = regExp.firstMatch(value);
      if (match == null) {
        throw FormatException(
          'Invalid date value for pattern yyyy-MM-dd',
          value,
        );
      }

      final int year = int.parse(match.group(1)!);
      final int month = int.parse(match.group(2)!);
      final int day = int.parse(match.group(3)!);
      return DateTime(year, month, day);
    }

    if (pattern == 'iso8601') {
      return DateTime.parse(value);
    }

    throw UnsupportedError('Unsupported date format pattern: $pattern');
  }

  /// Resets the global registry.
  static void reset() {
    _factories.clear();
    _encoders.clear();
    _unionTypeFields.clear();
    _unionFactories.clear();
  }

  /// Returns an immutable snapshot of the current
  /// registry state.
  static SerializerSnapshot snapshot() {
    return SerializerSnapshot._(
      factories: Map<Type, JsonFactory<dynamic>>.unmodifiable(_factories),
      encoders: Map<Type, JsonEncoder<dynamic>>.unmodifiable(_encoders),
      unionTypeFields: Map<Type, String>.unmodifiable(_unionTypeFields),
      unionFactories: Map<Type, Map<String, JsonFactory<dynamic>>>.unmodifiable(
        _unionFactories.map(
          (Type k, Map<String, JsonFactory<dynamic>> v) =>
              MapEntry<Type, Map<String, JsonFactory<dynamic>>>(
            k,
            Map<String, JsonFactory<dynamic>>.unmodifiable(v),
          ),
        ),
      ),
    );
  }

  static T _decodeMap<T>(Map<String, dynamic> json) {
    final Map<String, JsonFactory<dynamic>>? unionFactories =
        _unionFactories[T];
    if (unionFactories != null) {
      final String typeField = _unionTypeFields[T] ?? 'type';
      final dynamic rawDiscriminator = json[typeField];
      if (rawDiscriminator is! String || rawDiscriminator.isEmpty) {
        throw ArgumentError(
          'Missing or invalid discriminator for union $T at "$typeField".',
        );
      }

      final JsonFactory<dynamic>? unionFactory =
          unionFactories[rawDiscriminator];
      if (unionFactory == null) {
        throw ArgumentError(
          'Unknown discriminator "$rawDiscriminator" for union $T.',
        );
      }

      return unionFactory(json) as T;
    }

    final JsonFactory<dynamic>? factory = _factories[T];
    if (factory != null) {
      return factory(json) as T;
    }

    throw StateError(
      'Type $T is not registered. Call Serializer.register<$T>() first.',
    );
  }

  static Object? _encodeValue(Object? value) {
    for (final _ValueCodec codec in _valueCodecs) {
      if (codec.matches(value)) {
        return codec.encode(value, _encodeValue);
      }
    }

    final JsonEncoder<dynamic>? encoder = _encoders[value!.runtimeType];
    if (encoder == null) {
      throw StateError(
        'Type ${value.runtimeType} is not registered. '
        'Call Serializer.register<${value.runtimeType}>() first.',
      );
    }

    final Map<String, dynamic> json = encoder(value);
    return json.map(
      (String key, dynamic item) => MapEntry(key, _encodeValue(item)),
    );
  }

  /// Validates that the keys of [map] can be safely
  /// converted to JSON keys.
  static void validateMapKeys(Map<dynamic, dynamic> map) =>
      validateMapKeysImpl(map);
}
