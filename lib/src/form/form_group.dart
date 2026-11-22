import 'form_field_state.dart';
import 'form_array.dart';
import 'form_validation_state.dart';

/// A dynamically composable group of fields and nested form controls.
class FormGroup {
  FormGroup({Map<String, Object>? controls})
      : _controls = <String, Object>{...?controls};

  final Map<String, Object> _controls;

  Map<String, Object> get controls => Map<String, Object>.unmodifiable(_controls);

  Map<String, Object?> get value => _controls.map(
        (String name, Object control) => MapEntry<String, Object?>(
          name,
          _controlValue(control),
        ),
      );

  bool get isDirty => _controls.values.any(_controlIsDirty);
  bool get isPristine => !isDirty;

  FormValidationState get validationState {
    if (_controls.values.any(_controlIsValidating)) {
      return FormValidationState.validating;
    }
    return _controls.values.every(_controlIsValid)
        ? FormValidationState.valid
        : FormValidationState.invalid;
  }

  void add(String name, Object control) {
    if (!_isControl(control)) {
      throw ArgumentError.value(control, 'control', 'Unsupported form control');
    }
    if (_controls.containsKey(name)) {
      throw ArgumentError.value(name, 'name', 'Control already exists');
    }
    _controls[name] = control;
  }

  Object remove(String name) {
    final Object? removed = _controls.remove(name);
    if (removed == null) {
      throw ArgumentError.value(name, 'name', 'Unknown form control');
    }
    return removed;
  }

  FormFieldState<Object?> control(String name) {
    final Object? control = _controls[name];
    if (control is! FormFieldState<Object?>) {
      throw StateError('Control "$name" is not a field');
    }
    return control;
  }

  bool validate() {
    return _controls.values.map(_validateControl).every((bool valid) => valid);
  }

  Future<bool> validateAsync() async {
    final List<bool> results = await Future.wait(
      _controls.values.map(_validateControlAsync),
    );
    return results.every((bool valid) => valid);
  }

  void reset() {
    for (final Object control in _controls.values) {
      if (control is FormFieldState<Object?>) {
        control.reset();
      } else if (control is FormGroup) {
        control.reset();
      } else if (control is FormArray) {
        control.reset();
      }
    }
  }

  Future<void> dispose() async {
    for (final Object control in _controls.values) {
      await _disposeControl(control);
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

  static Future<void> _disposeControl(Object control) async {
    if (control is FormFieldState<Object?>) await control.dispose();
    if (control is FormGroup) await control.dispose();
    if (control is FormArray) await control.dispose();
  }
}
