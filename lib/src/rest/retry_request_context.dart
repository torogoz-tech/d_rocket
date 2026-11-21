import 'dart:async';

import 'cancel_token.dart';
import 'error.dart';
import 'rest_request.dart';

/// Request information available to a contextual retry decision.
class RetryRequestContext {
  const RetryRequestContext({
    required this.request,
    required this.error,
    required this.stackTrace,
    required this.attempt,
    this.cancelToken,
  });

  final RestRequest request;
  final Object error;
  final StackTrace stackTrace;
  final int attempt;
  final CancelToken? cancelToken;

  bool get cancelled =>
      cancelToken?.isCancelled == true || error is RequestCancelledException;

  bool get isTransientFailure {
    if (error is NetworkException || error is TimeoutException) return true;
    if (error is RestHttpException) {
      final int statusCode = (error as RestHttpException).statusCode;
      return statusCode == 408 || statusCode == 429 || statusCode >= 500;
    }
    return false;
  }

  bool get operationIsExplicitlyRetryable => request.retryable;

  bool get isIdempotent => const <String>{
        'GET',
        'HEAD',
        'OPTIONS',
        'PUT',
        'DELETE',
      }.contains(request.method.toUpperCase());
}
