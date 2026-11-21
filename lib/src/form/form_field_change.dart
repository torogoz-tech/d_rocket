/// Describes a value change emitted by a form field.
class FormFieldChange<T> {
  const FormFieldChange({required this.value, required this.rawValue});

  final T? value;
  final Object? rawValue;
}
