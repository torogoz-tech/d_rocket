/// Field-level serialisation customisations.
class JsonKey {
  /// Override for the generated JSON key.
  final String? name;

  /// Excludes this field from generated
  /// serialisation.
  final bool ignore;

  /// Default value used when the input key is
  /// missing or null.
  final dynamic defaultValue;

  /// Prefix for top-level converter functions:
  /// `XToJson` / `XFromJson`.
  final String? converter;

  /// Encodes enums by index instead of enum name.
  final bool useEnumIndex;

  /// Requires the key to be present and non-null
  /// during deserialisation.
  final bool requiredKey;

  /// Enum value name used when an unknown enum
  /// input is received.
  final String? unknownEnumValue;

  const JsonKey({
    this.name,
    this.ignore = false,
    this.defaultValue,
    this.converter,
    this.useEnumIndex = false,
    this.requiredKey = false,
    this.unknownEnumValue,
  });
}
