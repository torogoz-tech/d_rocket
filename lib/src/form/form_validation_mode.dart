/// Determines when a field or form runs validation.
enum FormValidationMode {
  /// Validates after every value change.
  onChange,

  /// Validates when a field is touched or loses focus.
  onBlur,

  /// Validates when the form submit operation calls [validate].
  onSubmit,

  /// Validates only when explicitly requested.
  manual,
}
