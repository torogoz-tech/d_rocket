import 'retry_decision.dart';
import 'retry_policy.dart';

/// Retry policy that always gives up. Use this to
/// opt out of the default exponential backoff
/// (e.g. for tests, or for transient-error-free
/// environments).
class NoRetryPolicy implements RetryPolicy {
  const NoRetryPolicy();

  @override
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    required StackTrace stackTrace,
  }) =>
      const RetryDecision.giveUp();
}
