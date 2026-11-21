// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'uuid_request.dart';

// **************************************************************************
// FormGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND

class UuidRequestForm {
  UuidRequestForm({
    String? initialRequestId,
    String? initialGeneralId,
    String? initialVersionedId,
    String? initialOptionalId,
    List<FormValidator<UuidRequest>> validators =
        const <FormValidator<UuidRequest>>[],
    FormValidationMode validationMode = FormValidationMode.onSubmit,
  }) : state = _createState(
          initialRequestId,
          initialGeneralId,
          initialVersionedId,
          initialOptionalId,
          validators,
          validationMode,
        );

  final FormState<UuidRequest> state;

  static const List<FormFieldDefinition> definitions = <FormFieldDefinition>[
    FormFieldDefinition(
        name: 'requestId', label: null, order: 0, input: FormInput.text),
    FormFieldDefinition(
        name: 'generalId', label: null, order: 0, input: FormInput.text),
    FormFieldDefinition(
        name: 'versionedId', label: null, order: 0, input: FormInput.text),
    FormFieldDefinition(
        name: 'optionalId', label: null, order: 0, input: FormInput.text),
  ];
  FormFieldState<String> get requestId =>
      state.fields['requestId']! as FormFieldState<String>;
  FormFieldState<String> get generalId =>
      state.fields['generalId']! as FormFieldState<String>;
  FormFieldState<String> get versionedId =>
      state.fields['versionedId']! as FormFieldState<String>;
  FormFieldState<String?> get optionalId =>
      state.fields['optionalId']! as FormFieldState<String?>;
  bool validate() => state.validate();
  UuidRequest build() => state.build();

  void Function(TValue) bindComposite<TValue>(
    Map<String, Object?> Function(TValue value) mapper,
  ) =>
      state.bindComposite(mapper);

  static FormState<UuidRequest> _createState(
    String? initialRequestId,
    String? initialGeneralId,
    String? initialVersionedId,
    String? initialOptionalId,
    List<FormValidator<UuidRequest>> validators,
    FormValidationMode validationMode,
  ) {
    final fields = <String, FormFieldState<Object?>>{
      'requestId': FormFieldState<String>(
        initialValue: initialRequestId,
        validators: <FormValidator<String>>[
          (value) => value is String &&
                  !RegExp('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\$')
                      .hasMatch(value)
              ? FormError(code: 'uuid.invalid', message: 'El UUID no es válido')
              : null,
        ],
      ),
      'generalId': FormFieldState<String>(
        initialValue: initialGeneralId,
        validators: <FormValidator<String>>[
          (value) => value is String &&
                  !RegExp('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\$')
                      .hasMatch(value)
              ? FormError(code: 'uuid.invalid', message: 'El UUID no es válido')
              : null,
        ],
      ),
      'versionedId': FormFieldState<String>(
        initialValue: initialVersionedId,
        validators: <FormValidator<String>>[
          (value) => value is String &&
                  !RegExp('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-7[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\$')
                      .hasMatch(value)
              ? FormError(code: 'uuid.invalid', message: 'El UUID no es válido')
              : null,
        ],
      ),
      'optionalId': FormFieldState<String?>(
        initialValue: initialOptionalId,
        validators: <FormValidator<String?>>[
          (value) => value is String &&
                  !RegExp('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\$')
                      .hasMatch(value)
              ? FormError(
                  code: 'optional.uuid.invalid',
                  message: 'UUID opcional inválido')
              : null,
        ],
      ),
    };
    final form = FormState<UuidRequest>(
      fields: fields,
      validators: validators,
      builder: () => UuidRequest(
        requestId: fields['requestId']!.value as String,
        generalId: fields['generalId']!.value as String,
        versionedId: fields['versionedId']!.value as String,
        optionalId: fields['optionalId']!.value as String?,
      ),
      validationMode: validationMode,
    );
    return form;
  }
}
