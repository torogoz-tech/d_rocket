/// Function used to convert a raw control value into a typed value.
typedef FormParseFunction<T> = T? Function(Object? rawValue);

/// Converts raw control values for a typed form field.
class FormValueParser<T> {
  /// Creates a parser from a conversion function.
  const FormValueParser({required FormParseFunction<T> parse}) : _parse = parse;

  final FormParseFunction<T> _parse;

  /// Converts [rawValue] into the field type.
  T? parse(Object? rawValue) => _parse(rawValue);
}
