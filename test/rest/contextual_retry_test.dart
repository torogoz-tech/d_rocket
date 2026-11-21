import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../support/contextual_retry_client.dart';

void main() {
  test('does not retry an ambiguous mutation by default', () async {
    final ContextualRetryClient inner = ContextualRetryClient(
      failuresBeforeSuccess: 3,
    );
    final RetryingHttpClient client = RetryingHttpClient(
      inner: inner,
      policy: ExponentialBackoffRetryPolicy(
        maxAttempts: 4,
        baseDelay: Duration.zero,
        jitter: Duration.zero,
      ),
    );

    await expectLater(
      client.execute(
        const RestRequest(method: 'POST', path: '/payments'),
        decoder: (dynamic value) => value,
      ),
      throwsA(isA<NetworkException>()),
    );

    expect(inner.requests, hasLength(1));
  });

  test('context callback retries an idempotent operation with stable payload',
      () async {
    final List<RetryRequestContext> contexts = <RetryRequestContext>[];
    final ContextualRetryClient inner = ContextualRetryClient(
      failuresBeforeSuccess: 2,
    );
    final RetryingHttpClient client = RetryingHttpClient(
      inner: inner,
      policy: ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: Duration.zero,
        jitter: Duration.zero,
      ),
      shouldRetryContext: (RetryRequestContext context) {
        contexts.add(context);
        return context.isTransientFailure &&
            context.request.method == 'GET' &&
            !context.cancelled;
      },
    );

    final RestResponse<dynamic> response = await client.execute(
      const RestRequest(
        method: 'GET',
        baseUrl: 'https://api.example.test',
        path: '/vehicles',
        body: '{"page":1}',
      ),
      decoder: (dynamic value) => value,
    );

    expect(response.statusCode, 200);
    expect(contexts.map((RetryRequestContext value) => value.attempt),
        <int>[1, 2]);
    expect(contexts.map((RetryRequestContext value) => value.request.fullUrl),
        everyElement('https://api.example.test/vehicles'));
    expect(inner.requests.map((RestRequest value) => value.body),
        everyElement('{"page":1}'));
  });

  test('cancellation interrupts retry backoff', () async {
    final CancelToken token = CancelToken();
    final ContextualRetryClient inner = ContextualRetryClient(
      failuresBeforeSuccess: 2,
    );
    final RetryingHttpClient client = RetryingHttpClient(
      inner: inner,
      policy: ExponentialBackoffRetryPolicy(
        maxAttempts: 3,
        baseDelay: const Duration(seconds: 1),
        jitter: Duration.zero,
      ),
      shouldRetryContext: (RetryRequestContext context) =>
          context.isTransientFailure && !context.cancelled,
    );

    final Future<RestResponse<dynamic>> request = client.execute(
      const RestRequest(method: 'GET', path: '/events'),
      decoder: (dynamic value) => value,
      cancelToken: token,
    );
    Timer(const Duration(milliseconds: 5), token.cancel);

    await expectLater(request, throwsA(isA<RequestCancelledException>()));
    expect(inner.requests, hasLength(1));
  });
}
