/// Field-level formatter configuration.
class Format {
  /// Formatter kind identifier used by codegen.
  final String kind;

  /// Optional formatter pattern, for example date
  /// patterns.
  final String? pattern;

  /// Optional formatter type for typed custom
  /// formatters.
  final Type? formatterType;

  const Format._(this.kind, {this.pattern, this.formatterType});

  /// Trims leading and trailing whitespace.
  const Format.trim() : this._('trim');

  /// Converts string values to uppercase.
  const Format.uppercase() : this._('uppercase');

  /// Converts string values to lowercase.
  const Format.lowercase() : this._('lowercase');

  /// Formats dates using a supported pattern.
  const Format.date(String pattern) : this._('date', pattern: pattern);

  /// Uses custom formatter functions:
  /// `XFormatToJson` and `XFormatFromJson`.
  const Format.custom(String name) : this._('custom', pattern: name);

  /// Uses typed custom formatter functions:
  /// `TypeNameFormatToJson` and
  /// `TypeNameFormatFromJson`.
  const Format.customWith(Type formatterType)
      : this._('customWith', formatterType: formatterType);
}
