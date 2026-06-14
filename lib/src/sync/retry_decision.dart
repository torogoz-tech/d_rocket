/// The decision returned by a [RetryPolicy.shouldRetry]
/// call.
class RetryDecision {
  /// Create a `retry` decision — wait [after] and
  /// re-attempt.
  const RetryDecision.retry(this.after) : isGiveUp = false;

  /// Create a `give up` decision — re-throw the error.
  const RetryDecision.giveUp()
      : isGiveUp = true,
        after = Duration.zero;

  /// Whether the policy wants the caller to give up.
  final bool isGiveUp;

  /// How long to wait before the next attempt (only
  /// valid when [isGiveUp] is `false`).
  final Duration after;
}
