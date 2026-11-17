import 'form_input.dart';

/// Describes the capture metadata generated for one form field.
class FormFieldDefinition {
  const FormFieldDefinition({
    required this.name,
    required this.label,
    required this.order,
    required this.input,
  });

  final String name;
  final String? label;
  final int order;
  final FormInput input;
}
