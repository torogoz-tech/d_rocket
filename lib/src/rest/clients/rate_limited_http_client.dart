//: a `HttpClient` that wraps another
// `HttpClient` and rate-limits the requests
// using a token bucket algorithm.
//
// Usage:
//
// ```dart
// final client = RateLimitedHttpClient(
// inner: HttpPackageClient,
// tokensPerSecond: 10, // 10 req/s sustained
// burst: 20, // up to 20 in a burst
//);
// ```
//
// The token bucket has `burst` tokens; each
// request consumes 1; tokens are refilled at
// `tokensPerSecond`. If the bucket is empty, the
// request blocks (async) until a token is
// available.

import 'dart:async';

import '../cancel_token.dart';
import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';

///: an [HttpClient] that wraps an
/// [inner] client and rate-limits the requests
/// using a token bucket. If the bucket is empty,
/// requests block until a token is available.
class RateLimitedHttpClient implements HttpClient {
  ///: creates a rate-limited wrapper.
  ///
  /// [tokensPerSecond] is the sustained rate
  /// (the bucket refills at this rate).
  ///
  /// [burst] is the maximum number of tokens the
  /// bucket can hold (and therefore the maximum
  /// number of requests that can be made in a
  /// burst).
  RateLimitedHttpClient({
    required this.inner,
    required this.tokensPerSecond,
    this.burst = 1,
  })  : _tokens = 0,
        _lastRefill = DateTime.now();

  final HttpClient inner;
  final double tokensPerSecond;
  final int burst;

  double _tokens;
  DateTime _lastRefill;
  final List<Completer<void>> _waiters = <Completer<void>>[];
  Timer? _refillTimer;

  ///: initial state — the bucket is
  /// full (so the first [burst] requests are
  /// immediate).
  RateLimitedHttpClient._unsafe({
    required this.inner,
    required this.tokensPerSecond,
    required this.burst,
    required double initialTokens,
    required DateTime lastRefill,
  })  : _tokens = initialTokens,
        _lastRefill = lastRefill;

  ///: factory for tests — exposes the
  /// initial state of the bucket.
  factory RateLimitedHttpClient.forTesting({
    required HttpClient inner,
    required double tokensPerSecond,
    required int burst,
    double initialTokens = 0,
  }) {
    return RateLimitedHttpClient._unsafe(
      inner: inner,
      tokensPerSecond: tokensPerSecond,
      burst: burst,
      initialTokens: burst.toDouble(),
      lastRefill: DateTime.now(),
    );
  }

  ///: the number of available tokens
  /// right now. Useful for tests.
  double get availableTokens => _tokens;

  void _refill() {
    final DateTime now = DateTime.now();
    final Duration elapsed = now.difference(_lastRefill);
    if (elapsed.inMicroseconds <= 0) return;
    final double newTokens =
        _tokens + (elapsed.inMicroseconds / 1e6) * tokensPerSecond;
    _tokens = newTokens > burst ? burst.toDouble() : newTokens;
    _lastRefill = now;
    // Wake up any waiters.
    while (_waiters.isNotEmpty && _tokens >= 1) {
      _tokens -= 1;
      _waiters.removeAt(0).complete();
    }
  }

  Future<void> _acquire() {
    _refill();
    if (_tokens >= 1) {
      _tokens -= 1;
      return Future<void>.value();
    }
    // Block until a token is available.
    final Completer<void> waiter = Completer<void>();
    _waiters.add(waiter);
    // Start the refill timer if not already.
    _refillTimer ??= Timer.periodic(
      const Duration(milliseconds: 10),
      (_) {
        _refill();
        if (_waiters.isEmpty) {
          _refillTimer?.cancel();
          _refillTimer = null;
        }
      },
    );
    return waiter.future;
  }

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    await _acquire();
    return inner.execute(request, decoder: decoder, cancelToken: cancelToken);
  }

  @override
  Future<void> close() async {
    _refillTimer?.cancel();
    _refillTimer = null;
    for (final Completer<void> w in _waiters) {
      w.complete();
    }
    _waiters.clear();
    await inner.close();
  }
}
