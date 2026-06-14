//: a `HttpClient` that wraps another
// `HttpClient` and retries failed requests with
// an exponential backoff (via [RetryPolicy]).
//
// Usage:
//
// ```dart
// final client = RetryingHttpClient(
// inner: HttpPackageClient,
// policy: ExponentialBackoffRetryPolicy(
// maxAttempts: 5,
// baseDelay: Duration(seconds: 1),
//),
//);
// dRest.client = client;
// ```

import 'dart:async';

import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';
import '../../sync/retry_decision.dart';
import '../cancel_token.dart';
import '../../sync/retry_policy.dart';

///: an [HttpClient] that wraps an
/// [inner] client and retries failed requests
/// using a [RetryPolicy]. On success the
/// response is returned. On failure the policy
/// is consulted: if it returns
/// [RetryDecision.retry], the request is re-sent
/// after the given delay. If it returns
/// [RetryDecision.giveUp], the last error is
/// re-thrown.
class RetryingHttpClient implements HttpClient {
  ///: creates a retrying wrapper.
  ///
  /// [inner] is the wrapped client (the actual
  /// HTTP transport). [policy] decides when to
  /// retry and how long to wait. [shouldRetry] is
  /// an optional filter — if it returns `false`,
  /// the request is NOT retried even if the
  /// policy would say yes (e.g. don't retry 4xx
  /// errors that are not 408/429).
  RetryingHttpClient({
    required this.inner,
    required this.policy,
    this.shouldRetry,
  });

  final HttpClient inner;
  final RetryPolicy policy;
  final bool Function(Object error)? shouldRetry;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await inner.execute(request,
            decoder: decoder, cancelToken: cancelToken);
      } catch (e, st) {
        // (filter): if the user
        // provided a filter and it says "no", we
        // don't retry.
        if (shouldRetry != null && !shouldRetry!(e)) rethrow;
        final RetryDecision decision = policy.shouldRetry(
          attempt: attempt,
          error: e,
          stackTrace: st,
        );
        if (decision.isGiveUp) rethrow;
        await Future<void>.delayed(decision.after);
        attempt++;
      }
    }
  }

  @override
  Future<void> close() async {
    await inner.close();
  }
}
