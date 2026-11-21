/// Detailed conversion failure raised by generated deserializers.
class SerializationException extends ArgumentError {
  SerializationException({
    required this.field,
    required this.expectedType,
    required this.rawValue,
    required this.cause,
    required this.stackTrace,
  }) : super(cause);

  final String field;
  final String expectedType;
  final Object? rawValue;
  final Object cause;
  @override
  final StackTrace stackTrace;

  @override
  String toString() =>
      'SerializationException at $field: expected $expectedType, '
      'received ${rawValue.runtimeType}: $cause';
}
