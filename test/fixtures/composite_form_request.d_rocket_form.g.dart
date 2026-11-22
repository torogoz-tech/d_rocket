// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'composite_form_request.dart';

// **************************************************************************
// FormGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND

class CompositeFormRequestForm {
  CompositeFormRequestForm({
    String? initialExpiry,
    String? initialExpiryMonth,
    String? initialExpiryYear,
    List<FormValidator<CompositeFormRequest>> validators =
        const <FormValidator<CompositeFormRequest>>[],
    List<AsyncFormValidator<CompositeFormRequest>> asyncValidators =
        const <AsyncFormValidator<CompositeFormRequest>>[],
    Duration? asyncValidationDebounce,
    FormValidationMode validationMode = FormValidationMode.onSubmit,
  }) : state = _createState(
          initialExpiry,
          initialExpiryMonth,
          initialExpiryYear,
          validators,
          asyncValidators,
          asyncValidationDebounce,
          validationMode,
        );

  final FormState<CompositeFormRequest> state;

  static const List<FormFieldDefinition> definitions = <FormFieldDefinition>[
    FormFieldDefinition(
        name: 'expiry',
        label: null,
        order: 0,
        input: FormInput.text,
        binding: <String>['expiryMonth', 'expiryYear']),
    FormFieldDefinition(
        name: 'expiryMonth',
        label: null,
        order: 0,
        input: FormInput.text,
        binding: const <String>[]),
    FormFieldDefinition(
        name: 'expiryYear',
        label: null,
        order: 0,
        input: FormInput.text,
        binding: const <String>[]),
  ];
  FormFieldState<String> get expiry =>
      state.fields['expiry']! as FormFieldState<String>;
  FormFieldState<String> get expiryMonth =>
      state.fields['expiryMonth']! as FormFieldState<String>;
  FormFieldState<String> get expiryYear =>
      state.fields['expiryYear']! as FormFieldState<String>;
  bool validate() => state.validate();
  Future<bool> validateAsync() => state.validateAsync();
  CompositeFormRequest build() => state.build();
  Future<CompositeFormRequest> buildAsync() => state.buildAsync();
  void applyRestError(RestHttpException error) => state.applyRestError(error);

  void Function(TValue) bindComposite<TValue>(
    Map<String, Object?> Function(TValue value) mapper,
  ) =>
      state.bindComposite(mapper);

  static FormState<CompositeFormRequest> _createState(
    String? initialExpiry,
    String? initialExpiryMonth,
    String? initialExpiryYear,
    List<FormValidator<CompositeFormRequest>> validators,
    List<AsyncFormValidator<CompositeFormRequest>> asyncValidators,
    Duration? asyncValidationDebounce,
    FormValidationMode validationMode,
  ) {
    final fields = <String, FormFieldState<Object?>>{
      'expiry': FormFieldState<String>(
        initialValue: initialExpiry,
        validators: <FormValidator<String>>[],
      ),
      'expiryMonth': FormFieldState<String>(
        initialValue: initialExpiryMonth,
        validators: <FormValidator<String>>[],
      ),
      'expiryYear': FormFieldState<String>(
        initialValue: initialExpiryYear,
        validators: <FormValidator<String>>[],
      ),
    };
    final form = FormState<CompositeFormRequest>(
      fields: fields,
      validators: validators,
      asyncValidators: asyncValidators,
      asyncValidationDebounce: asyncValidationDebounce,
      builder: () => CompositeFormRequest(
        expiry: fields['expiry']!.value as String,
        expiryMonth: fields['expiryMonth']!.value as String,
        expiryYear: fields['expiryYear']!.value as String,
      ),
      validationMode: validationMode,
    );
    return form;
  }
}
