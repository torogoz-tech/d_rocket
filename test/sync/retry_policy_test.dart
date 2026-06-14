// (retry): tests for the retry
// policy + the wiring in ctx.syncAsync.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.16 — ExponentialBackoffRetryPolicy: shape', () {
    test('attempts < maxAttempts → retry', () {
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 100),
        jitter: Duration.zero,
      );
      // attempt = 0 (1st retry, since the
      // initial attempt is attempt 0).
      final RetryDecision d = policy.shouldRetry(
        attempt: 0,
        error: Exception('boom'),
        stackTrace: StackTrace.current,
      );
      expect(d.isGiveUp, isFalse);
      expect(d.after.inMilliseconds, 100); // 100 * 2^0
    });

    test('attempt + 1 = maxAttempts → give up', () {
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 100),
        jitter: Duration.zero,
      );
      // attempt=2 means we've already done 3
      // calls (0, 1, 2). With maxAttempts=3, we
      // give up.
      final RetryDecision d = policy.shouldRetry(
        attempt: 2,
        error: Exception('boom'),
        stackTrace: StackTrace.current,
      );
      expect(d.isGiveUp, isTrue);
    });

    test('exponential growth: 100ms, 200ms, 400ms (no jitter)', () {
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 5,
        baseDelay: const Duration(milliseconds: 100),
        factor: 2,
        jitter: Duration.zero,
      );
      // attempt=0: 100ms; attempt=1: 200ms;
      // attempt=2: 400ms.
      final List<Duration> delays = <Duration>[
        for (int i = 0; i < 3; i++)
          policy
              .shouldRetry(
                attempt: i,
                error: Exception(),
                stackTrace: StackTrace.current,
              )
              .after,
      ];
      expect(delays[0].inMilliseconds, 100);
      expect(delays[1].inMilliseconds, 200);
      expect(delays[2].inMilliseconds, 400);
    });

    test('maxDelay caps the exponential growth', () {
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 20,
        baseDelay: const Duration(seconds: 1),
        factor: 2,
        maxDelay: const Duration(seconds: 5),
        jitter: Duration.zero,
      );
      // attempt=10 would be 1024s but capped to 5s.
      final RetryDecision d = policy.shouldRetry(
        attempt: 10,
        error: Exception(),
        stackTrace: StackTrace.current,
      );
      expect(d.after.inMilliseconds, 5000);
    });
  });

  group('Fase 5.16 — NoRetryPolicy: shape', () {
    test('always gives up', () {
      const NoRetryPolicy policy = NoRetryPolicy();
      expect(
        policy
            .shouldRetry(
              attempt: 0,
              error: Exception(),
              stackTrace: StackTrace.current,
            )
            .isGiveUp,
        isTrue,
      );
    });
  });

  group('Fase 5.16 — ctx.syncAsync: retry integration', () {
    test('a flaky provider succeeds on the 2nd attempt', () async {
      // Provider that fails on the 1st call,
      // then succeeds.
      final _FlakyProvider provider = _FlakyProvider(failuresBeforeSuccess: 1);
      final _RetryContext ctx = _RetryContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      // Use a fast backoff (10ms base).
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 10),
        jitter: Duration.zero,
      );
      // Sync — should succeed on the 2nd attempt.
      await ctx.syncAsync(provider, retryPolicy: policy);
      // 2 calls were made.
      expect(provider.callCount, 2);
    });

    test('exhausted retries re-throw the error', () async {
      final _FlakyProvider provider =
          _FlakyProvider(failuresBeforeSuccess: 100);
      final _RetryContext ctx = _RetryContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      final ExponentialBackoffRetryPolicy policy =
          ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(milliseconds: 1),
        jitter: Duration.zero,
      );
      await expectLater(
        ctx.syncAsync(provider, retryPolicy: policy),
        throwsA(isA<Exception>()),
      );
      // 3 calls (initial + 2 retries).
      expect(provider.callCount, 3);
    });

    test('a successful first attempt does not retry', () async {
      final _FlakyProvider provider = _FlakyProvider(failuresBeforeSuccess: 0);
      final _RetryContext ctx = _RetryContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      await ctx.syncAsync(provider, retryPolicy: const NoRetryPolicy());
      expect(provider.callCount, 1);
    });
  });
}

/// Test helper: a [SyncProvider] that fails
/// N times before succeeding. Each call to
/// [syncAsync] is counted.
class _FlakyProvider implements SyncProvider {
  _FlakyProvider({this.failuresBeforeSuccess = 0});
  int failuresBeforeSuccess;
  int callCount = 0;

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    callCount++;
    if (callCount <= failuresBeforeSuccess) {
      throw Exception('flaky failure #$callCount');
    }
    return SyncEnvelope(
      clientId: envelope.clientId,
      since: callCount,
      changes: const <SyncChange>[],
    );
  }

  @override
  Future<int> currentWatermarkAsync() async => callCount;
}

class _RetryContext extends DbContext {
  @override
  AsyncQueryProvider? get asyncProvider => null;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}
