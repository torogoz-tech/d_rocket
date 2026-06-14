import 'retry_decision.dart';

/// Pluggable retry policy. Implementations:
/// * [ExponentialBackoffRetryPolicy] — the default.
/// * [NoRetryPolicy] — op-out.
abstract class RetryPolicy {
  /// Decide whether to retry after [attempt] failures.
  ///
  /// * [attempt] is the number of failures so far
  /// (0-indexed — 0 means the first attempt
  /// failed).
  /// * [error] is the last error.
  /// * [stackTrace] is its stack trace.
  ///
  /// Returns a [RetryDecision] (either `retry` with
  /// a delay, or `giveUp`).
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    required StackTrace stackTrace,
  });
}
