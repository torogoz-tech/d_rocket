import 'form_field_state.dart';
import 'form_group.dart';
import 'form_validation_state.dart';

/// A dynamically sized ordered collection of form controls.
class FormArray {
  FormArray({List<Object>? controls}) : _controls = <Object>[...?controls];

  final List<Object> _controls;

  List<Object> get controls => List<Object>.unmodifiable(_controls);

  List<Object?> get value => _controls.map(_controlValue).toList();

  bool get isDirty => _controls.any(_controlIsDirty);
  bool get isPristine => !isDirty;

  FormValidationState get validationState {
    if (_controls.any(_controlIsValidating)) {
      return FormValidationState.validating;
    }
    return _controls.every(_controlIsValid)
        ? FormValidationState.valid
        : FormValidationState.invalid;
  }

  void add(Object control) {
    if (!_isControl(control)) {
      throw ArgumentError.value(control, 'control', 'Unsupported form control');
    }
    _controls.add(control);
  }

  Object removeAt(int index) => _controls.removeAt(index);

  bool validate() => _controls.map(_validateControl).every((bool valid) => valid);

  Future<bool> validateAsync() async {
    final List<bool> results = await Future.wait(
      _controls.map(_validateControlAsync),
    );
    return results.every((bool valid) => valid);
  }

  void reset() {
    for (final Object control in _controls) {
      if (control is FormFieldState<Object?>) control.reset();
      if (control is FormGroup) control.reset();
      if (control is FormArray) control.reset();
    }
  }

  Future<void> dispose() async {
    for (final Object control in _controls) {
      if (control is FormFieldState<Object?>) await control.dispose();
      if (control is FormGroup) await control.dispose();
      if (control is FormArray) await control.dispose();
    }
  }

  static bool _isControl(Object control) =>
      control is FormFieldState<Object?> ||
      control is FormGroup ||
      control is FormArray;

  static Object? _controlValue(Object control) {
    if (control is FormFieldState<Object?>) return control.value;
    if (control is FormGroup) return control.value;
    if (control is FormArray) return control.value;
    throw ArgumentError.value(control, 'control', 'Unsupported form control');
  }

  static bool _controlIsDirty(Object control) {
    if (control is FormFieldState<Object?>) return control.isDirty;
    if (control is FormGroup) return control.isDirty;
    if (control is FormArray) return control.isDirty;
    return false;
  }

  static bool _controlIsValidating(Object control) {
    if (control is FormFieldState<Object?>) {
      return control.validationState == FormValidationState.validating;
    }
    if (control is FormGroup) {
      return control.validationState == FormValidationState.validating;
    }
    if (control is FormArray) {
      return control.validationState == FormValidationState.validating;
    }
    return false;
  }

  static bool _controlIsValid(Object control) {
    if (control is FormFieldState<Object?>) return !control.hasError;
    if (control is FormGroup) return control.validationState == FormValidationState.valid;
    if (control is FormArray) return control.validationState == FormValidationState.valid;
    return false;
  }

  static bool _validateControl(Object control) {
    if (control is FormFieldState<Object?>) return control.validate();
    if (control is FormGroup) return control.validate();
    if (control is FormArray) return control.validate();
    return false;
  }

  static Future<bool> _validateControlAsync(Object control) {
    if (control is FormFieldState<Object?>) return control.validateAsync();
    if (control is FormGroup) return control.validateAsync();
    if (control is FormArray) return control.validateAsync();
    return Future<bool>.value(false);
  }
}
