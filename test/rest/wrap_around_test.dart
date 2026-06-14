//: tests for the 3 wrap-around
// HTTP clients (Retrying, RateLimited,
// CircuitBreaker). Uses a real `HttpServer.bind`
// to stand up a local server (no mocking).

import 'dart:async';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket/src/rest/clients/circuit_open_exception.dart';
import 'package:d_rocket/src/rest/clients/circuit_state.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 6.3 — RetryingHttpClient: real server', () {
    late HttpServer server;
    late Uri baseUri;
    int requestCount = 0;

    setUp(() async {
      requestCount = 0;
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((HttpRequest request) async {
        requestCount++;
        if (requestCount < 3) {
          request.response.statusCode = 503;
          await request.response.close();
          return;
        }
        request.response.statusCode = 200;
        request.response.headers.contentType =
            ContentType('application', 'json');
        request.response.write('{"ok":true}');
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('retries on 503 and eventually succeeds', () async {
      final RetryingHttpClient client = RetryingHttpClient(
        inner: HttpPackageClient(),
        policy: ExponentialBackoffRetryPolicy(
          maxAttempts: 5,
          baseDelay: const Duration(milliseconds: 1),
          jitter: Duration.zero,
        ),
      );
      final RestResponse<dynamic> resp = await client.execute(
        RestRequest(method: 'GET', path: '/', baseUrl: baseUri.toString()),
        decoder: (dynamic d) => d,
      );
      expect(resp.statusCode, 200);
      expect(requestCount, 3);
    });

    test('gives up after maxAttempts', () async {
      await server.close(force: true);
      requestCount = 0;
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUri = Uri.parse('http://127.0.0.1:${server.port}');
      server.listen((HttpRequest request) async {
        requestCount++;
        request.response.statusCode = 503;
        await request.response.close();
      });
      final RetryingHttpClient client = RetryingHttpClient(
        inner: HttpPackageClient(),
        policy: ExponentialBackoffRetryPolicy(
          maxAttempts: 3,
          baseDelay: const Duration(milliseconds: 1),
          jitter: Duration.zero,
        ),
      );
      await expectLater(
        client.execute(
          RestRequest(method: 'GET', path: '/', baseUrl: baseUri.toString()),
          decoder: (dynamic d) => d,
        ),
        throwsA(isA<Exception>()),
      );
      expect(requestCount, 3);
    });
  });

  group('Fase 6.3 — RateLimitedHttpClient: token bucket', () {
    test('the first `burst` requests are immediate', () async {
      int callCount = 0;
      final _CountingClient inner = _CountingClient(() => callCount++);
      final RateLimitedHttpClient rl = RateLimitedHttpClient(
        inner: inner,
        tokensPerSecond: 1,
        burst: 5,
      );
      for (int i = 0; i < 5; i++) {
        await rl.execute(
          RestRequest(method: 'GET', path: '/'),
          decoder: (dynamic d) => d,
        );
      }
      expect(callCount, 5);
      await rl.close();
    });

    test('a 6th request blocks until a token is available', () async {
      int callCount = 0;
      final _CountingClient inner = _CountingClient(() => callCount++);
      final RateLimitedHttpClient rl = RateLimitedHttpClient(
        inner: inner,
        tokensPerSecond: 100,
        burst: 2,
      );
      await rl.execute(RestRequest(method: 'GET', path: '/'),
          decoder: (dynamic d) => d);
      await rl.execute(RestRequest(method: 'GET', path: '/'),
          decoder: (dynamic d) => d);
      final Future<void> third = rl.execute(
        RestRequest(method: 'GET', path: '/'),
        decoder: (dynamic d) => d,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(callCount, 2);
      await third.timeout(const Duration(seconds: 1));
      expect(callCount, 3);
      await rl.close();
    });
  });

  group('Fase 6.3 — CircuitBreakerHttpClient: lifecycle', () {
    test('opens after N consecutive failures and rejects immediately',
        () async {
      int callCount = 0;
      final _FailingClient inner = _FailingClient(() => callCount++);
      final CircuitBreakerHttpClient cb = CircuitBreakerHttpClient(
        inner: inner,
        failureThreshold: 3,
        openDuration: const Duration(seconds: 30),
      );
      for (int i = 0; i < 3; i++) {
        await expectLater(
          cb.execute(
            RestRequest(method: 'GET', path: '/'),
            decoder: (dynamic d) => d,
          ),
          throwsA(isA<Exception>()),
        );
      }
      expect(cb.state, CircuitState.open);
      final int before4 = callCount;
      await expectLater(
        cb.execute(
          RestRequest(method: 'GET', path: '/'),
          decoder: (dynamic d) => d,
        ),
        throwsA(isA<CircuitOpenException>()),
      );
      expect(callCount, before4);
    });

    test('half-open after openDuration, closes on success', () async {
      final _CountedFailingClient inner = _CountedFailingClient(
        onCall: (int n) {
          // First 2 calls fail (open the circuit).
          // 3rd call (the half-open probe) succeeds.
          if (n <= 2) throw Exception('failing #$n');
          return RestResponse<dynamic>(
            statusCode: 200,
            headers: const <String, String>{},
            body: null,
            rawBody: '',
            request: RestRequest(method: 'GET', path: '/'),
          );
        },
      );
      final CircuitBreakerHttpClient cb = CircuitBreakerHttpClient(
        inner: inner,
        failureThreshold: 2,
        openDuration: const Duration(milliseconds: 1),
      );
      for (int i = 0; i < 2; i++) {
        await expectLater(
          cb.execute(
            RestRequest(method: 'GET', path: '/'),
            decoder: (dynamic d) => d,
          ),
          throwsA(isA<Exception>()),
        );
      }
      expect(cb.state, CircuitState.open);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // Half-open probe: success closes the circuit.
      final RestResponse<dynamic> probe = await cb.execute(
        RestRequest(method: 'GET', path: '/'),
        decoder: (dynamic d) => d,
      );
      expect(probe.statusCode, 200);
      expect(cb.state, CircuitState.closed);
    });
  });
}

class _CountingClient implements HttpClient {
  _CountingClient(this.onCall);
  final void Function() onCall;
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    onCall();
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{},
      body: null,
      rawBody: '',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}

class _FailingClient implements HttpClient {
  _FailingClient(this.onCall);
  final void Function() onCall;
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    onCall();
    throw Exception('inner failure');
  }

  @override
  Future<void> close() async {}
}

class _CountedFailingClient implements HttpClient {
  _CountedFailingClient({required this.onCall});
  final RestResponse<dynamic> Function(int callNumber) onCall;
  int _n = 0;
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    _n++;
    return onCall(_n);
  }

  @override
  Future<void> close() async {}
}
