//: exponential backoff with optional
// jitter. The default retry policy for sync.

import 'dart:math';

import 'retry_decision.dart';
import 'retry_policy.dart';

class ExponentialBackoffRetryPolicy implements RetryPolicy {
  /// Creates the policy.
  ///
  /// [maxAttempts] is the total number of
  /// attempts (including the first). So with
  /// `maxAttempts: 5`, the caller will make 5
  /// attempts before giving up.
  ExponentialBackoffRetryPolicy({
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 1),
    this.factor = 2,
    this.maxDelay = const Duration(seconds: 30),
    this.jitter = const Duration(milliseconds: 100),
    Random? random,
  }) : _random = random ?? Random();

  /// Total attempts (including the first). Default 5.
  final int maxAttempts;

  /// Base delay (the first retry waits this long).
  /// Default 1s.
  final Duration baseDelay;

  /// Multiplicative factor. Default 2 (so delays
  /// grow as 1s, 2s, 4s, 8s, 16s).
  final double factor;

  /// Cap on the delay. Default 30s.
  final Duration maxDelay;

  /// Jitter range (a random offset in
  /// `[-jitter, +jitter]` is added to each delay).
  /// Default 100ms.
  final Duration jitter;

  final Random _random;

  @override
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    required StackTrace stackTrace,
  }) {
    // `attempt` is the number of failures so far
    // (0-indexed). `maxAttempts` is the total
    // number of attempts. So we give up when
    // `attempt + 1 >= maxAttempts`.
    if (attempt + 1 >= maxAttempts) return const RetryDecision.giveUp();
    final double exp = baseDelay.inMilliseconds * _pow(factor, attempt);
    final int expMs = exp.round().clamp(0, maxDelay.inMilliseconds);
    final int jitterMs =
        _random.nextInt(2 * jitter.inMilliseconds + 1) - jitter.inMilliseconds;
    final int totalMs = (expMs + jitterMs).clamp(0, maxDelay.inMilliseconds);
    return RetryDecision.retry(Duration(milliseconds: totalMs));
  }
}

double _pow(double base, int exponent) {
  double result = 1;
  for (int i = 0; i < exponent; i++) {
    result *= base;
  }
  return result;
}
