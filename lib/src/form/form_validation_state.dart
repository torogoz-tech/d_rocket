/// Current state of synchronous or asynchronous form validation.
enum FormValidationState {
  /// No validation has completed for the current value.
  idle,

  /// An asynchronous validation is in progress.
  validating,

  /// The current value passed all configured validators.
  valid,

  /// One or more validators rejected the current value.
  invalid,
}
