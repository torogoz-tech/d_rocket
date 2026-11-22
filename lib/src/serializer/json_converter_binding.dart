/// Binds a registered converter expression to a Dart type for a generated
/// serializable model.
class JsonConverterBinding {
  const JsonConverterBinding({
    required this.typeName,
    required this.converter,
  });

  final String typeName;
  final String converter;
}
