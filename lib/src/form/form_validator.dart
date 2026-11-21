import 'dart:async';

import 'form_error.dart';

/// Produces an error synchronously when a typed value is invalid.
typedef FormValidator<T> = FormError? Function(T? value);

/// Produces an error asynchronously, for example after a remote lookup.
typedef AsyncFormValidator<T> = FutureOr<FormError?> Function(T? value);
