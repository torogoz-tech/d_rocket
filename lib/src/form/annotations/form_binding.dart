/// Declares the model fields populated by one composite control.
class FormBinding {
  const FormBinding({required this.fields});

  /// Target model field names in the order supplied by the control adapter.
  final List<String> fields;
}
