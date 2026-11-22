import '../form_input.dart';
import 'form_binding.dart';

/// Describes how a model field is presented by a form adapter.
class FormField {
  /// Creates form presentation metadata for a model field.
  const FormField({
    this.label,
    this.order = 0,
    this.input = FormInput.text,
    this.binding,
  });

  /// Optional human-readable label.
  final String? label;

  /// Relative display order for generated metadata.
  final int order;

  /// Suggested control kind for the field.
  final FormInput input;

  /// Optional declaration for a control that fills multiple model fields.
  final FormBinding? binding;
}
