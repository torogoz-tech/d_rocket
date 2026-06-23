/// 2.0.0 — additional retry policies.
///
/// In addition to the
/// [ExponentialBackoffRetryPolicy] (1.x) and
/// [NoRetryPolicy] (1.x), 2.0.0 ships:
///
/// * [DecorrelatedJitterRetryPolicy] — the
///   AWS-recommended retry policy. Lower
///   collision rate than vanilla exponential
///   backoff in multi-client scenarios.
/// * [LinearBackoffRetryPolicy] — fixed
///   delay between attempts. Good for known
///   transient failures (e.g. server restart
///   that takes 5s).
/// * [FibonacciBackoffRetryPolicy] — Fibonacci-
///   spaced delays. Smoother than exponential.
library;

import 'dart:math';

import 'retry_decision.dart';
import 'retry_policy.dart';

/// The [DecorrelatedJitterRetryPolicy] from the
/// AWS architecture blog. The next delay is
/// uniformly distributed between
/// `baseDelay` and `min(cap, prevDelay * 3)`.
///
/// Reference:
/// https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
class DecorrelatedJitterRetryPolicy implements RetryPolicy {
  /// Creates a [DecorrelatedJitterRetryPolicy]
  /// with [baseDelay] (default 100ms),
  /// [cap] (default 30s), and
  /// [maxAttempts] (default 5).
  DecorrelatedJitterRetryPolicy({
    this.baseDelay = const Duration(milliseconds: 100),
    this.cap = const Duration(seconds: 30),
    this.maxAttempts = 5,
    int? randomSeed,
  }) : _random = randomSeed == null ? Random() : Random(randomSeed);

  final Duration baseDelay;
  final Duration cap;
  final int maxAttempts;
  final Random _random;
  Duration _prev = Duration.zero;

  @override
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (attempt >= maxAttempts) {
      return const RetryDecision.giveUp();
    }
    final Duration low = _prev == Duration.zero ? baseDelay : _prev * 3;
    final Duration upper = low > cap ? cap : low;
    final int lowUs = baseDelay.inMicroseconds;
    final int upperUs = upper.inMicroseconds;
    final int nextUs =
        lowUs + _random.nextInt(upperUs - lowUs + 1).clamp(0, 1 << 31);
    _prev = Duration(microseconds: nextUs);
    return RetryDecision.retry(Duration(microseconds: nextUs));
  }
}

/// Fixed delay between attempts.
class LinearBackoffRetryPolicy implements RetryPolicy {
  /// Creates a [LinearBackoffRetryPolicy] with
  /// [delay] between attempts (default 1s) and
  /// [maxAttempts] (default 3).
  LinearBackoffRetryPolicy({
    this.delay = const Duration(seconds: 1),
    this.maxAttempts = 3,
  });

  final Duration delay;
  final int maxAttempts;

  @override
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (attempt >= maxAttempts) {
      return const RetryDecision.giveUp();
    }
    return RetryDecision.retry(delay);
  }
}

/// Fibonacci-spaced delays: 1, 1, 2, 3, 5, 8,
/// 13, ... * unitDelay.
class FibonacciBackoffRetryPolicy implements RetryPolicy {
  /// Creates a [FibonacciBackoffRetryPolicy]
  /// with [unitDelay] (default 1s) and
  /// [maxAttempts] (default 5).
  FibonacciBackoffRetryPolicy({
    this.unitDelay = const Duration(seconds: 1),
    this.maxAttempts = 5,
  });

  final Duration unitDelay;
  final int maxAttempts;

  @override
  RetryDecision shouldRetry({
    required int attempt,
    required Object error,
    StackTrace? stackTrace,
  }) {
    if (attempt >= maxAttempts) {
      return const RetryDecision.giveUp();
    }
    // Fibonacci: 1, 1, 2, 3, 5, 8, 13
    final List<int> fib = <int>[1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144];
    final int multiplier = attempt < fib.length ? fib[attempt] : fib.last;
    return RetryDecision.retry(unitDelay * multiplier);
  }
}
