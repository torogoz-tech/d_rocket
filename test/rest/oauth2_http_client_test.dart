// 2.0.0 — OAuth2HttpClient tests.

import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('OAuth2Token:', () {
    test('authorizationHeader is "Bearer <access>"', () {
      final OAuth2Token t = OAuth2Token.nonExpiring(
        accessToken: 'abc',
        refreshToken: 'xyz',
      );
      expect(t.authorizationHeader, 'Bearer abc');
    });

    test('custom token type is respected', () {
      final OAuth2Token t = OAuth2Token(
        accessToken: 'abc',
        refreshToken: 'xyz',
        expiresAt: DateTime.utc(3000),
        tokenType: 'MAC',
      );
      expect(t.authorizationHeader, 'MAC abc');
    });

    test('isExpired returns true past the expiry', () {
      final OAuth2Token t = OAuth2Token(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(t.isExpired(), isTrue);
    });

    test('isExpired returns false within the buffer', () {
      final OAuth2Token t = OAuth2Token(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 5)),
      );
      expect(t.isExpired(), isFalse);
    });

    test('fromJson parses a standard OAuth2 token response', () {
      final OAuth2Token t = OAuth2Token.fromJson(<String, Object?>{
        'access_token': 'NEW',
        'refresh_token': 'REFRESH',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'read write',
      });
      expect(t.accessToken, 'NEW');
      expect(t.refreshToken, 'REFRESH');
      expect(t.tokenType, 'Bearer');
      expect(t.scope, 'read write');
      expect(
        t.expiresAt.difference(DateTime.now()).inSeconds,
        inInclusiveRange(3590, 3610),
      );
    });
  });

  group('InMemoryOAuth2TokenStore:', () {
    test('starts empty', () async {
      final InMemoryOAuth2TokenStore s = InMemoryOAuth2TokenStore();
      expect(await s.read(), isNull);
    });

    test('write then read', () async {
      final InMemoryOAuth2TokenStore s = InMemoryOAuth2TokenStore();
      await s.write(OAuth2Token.nonExpiring(
        accessToken: 'a',
        refreshToken: 'r',
      ));
      final OAuth2Token? t = await s.read();
      expect(t, isNotNull);
      expect(t!.accessToken, 'a');
    });

    test('clear empties', () async {
      final InMemoryOAuth2TokenStore s = InMemoryOAuth2TokenStore(
        OAuth2Token.nonExpiring(accessToken: 'a', refreshToken: 'r'),
      );
      await s.clear();
      expect(await s.read(), isNull);
    });
  });

  group('OAuth2HttpClient (mock inner):', () {
    test('injects Authorization header on every request', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore(
        OAuth2Token.nonExpiring(accessToken: 'INIT', refreshToken: 'INIT_R'),
      );
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (_) async => throw StateError('should not refresh'),
      );
      // Mock inner returns 200.
      inner.nextResponse = _okResponse('{}');
      final RestResponse<dynamic> response = await client.execute(
        RestRequest(
          method: 'GET',
          path: '/foo',
          baseUrl: 'https://x',
          headers: const <String, String>{},
        ),
        decoder: _identityDecoder<dynamic>(),
      );
      expect(response.statusCode, 200);
      // Inner should have seen the Authorization
      // header.
      expect(inner.lastRequest!.headers['Authorization'], 'Bearer INIT');
    });

    test('catches 401, refreshes, retries with new token', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore(
        OAuth2Token.nonExpiring(accessToken: 'OLD', refreshToken: 'OLD_R'),
      );
      int refreshCount = 0;
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (OAuth2Token current) async {
          refreshCount++;
          return OAuth2Token.nonExpiring(
            accessToken: 'NEW',
            refreshToken: 'NEW_R',
          );
        },
      );
      // First call returns 401; second call (the
      // retry) returns 200.
      inner.responses.addAll(<RestResponse<dynamic>>[
        _response(401, '{}'),
        _okResponse('{}'),
      ]);
      final RestResponse<dynamic> response = await client.execute(
        RestRequest(
          method: 'GET',
          path: '/foo',
          baseUrl: 'https://x',
          headers: const <String, String>{},
        ),
        decoder: _identityDecoder<dynamic>(),
      );
      expect(response.statusCode, 200);
      expect(refreshCount, 1);
      // The store should have the new token.
      final OAuth2Token? t = await store.read();
      expect(t, isNotNull);
      expect(t!.accessToken, 'NEW');
      // The second request should have used
      // the new bearer.
      expect(
        inner.requests[1].headers['Authorization'],
        'Bearer NEW',
      );
    });

    test('proactively refreshes an expired token', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore(
        OAuth2Token(
          accessToken: 'OLD',
          refreshToken: 'OLD_R',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      int refreshCount = 0;
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (OAuth2Token current) async {
          refreshCount++;
          return OAuth2Token.nonExpiring(
            accessToken: 'NEW',
            refreshToken: 'NEW_R',
          );
        },
      );
      inner.nextResponse = _okResponse('{}');
      await client.execute(
        RestRequest(
          method: 'GET',
          path: '/foo',
          baseUrl: 'https://x',
          headers: const <String, String>{},
        ),
        decoder: _identityDecoder<dynamic>(),
      );
      // The expired token triggered a refresh.
      expect(refreshCount, 1);
      // The request used the NEW token.
      expect(inner.lastRequest!.headers['Authorization'], 'Bearer NEW');
    });

    test('throws if no token and no initialFn', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore();
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (_) async => throw StateError('unreachable'),
      );
      expect(
        () => client.execute(
          RestRequest(
            method: 'GET',
            path: '/foo',
            baseUrl: 'https://x',
            headers: const <String, String>{},
          ),
          decoder: _identityDecoder<dynamic>(),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('uses initialFn when store is empty', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore();
      inner.nextResponse = _okResponse('{}');
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (_) async => throw StateError('unreachable'),
        initialFn: () async => OAuth2Token.nonExpiring(
          accessToken: 'INIT',
          refreshToken: 'INIT_R',
        ),
      );
      await client.execute(
        RestRequest(
          method: 'GET',
          path: '/foo',
          baseUrl: 'https://x',
          headers: const <String, String>{},
        ),
        decoder: _identityDecoder<dynamic>(),
      );
      expect(inner.lastRequest!.headers['Authorization'], 'Bearer INIT');
      // The store was written to.
      final OAuth2Token? t = await store.read();
      expect(t, isNotNull);
      expect(t!.accessToken, 'INIT');
    });

    test('non-401 errors are not retried', () async {
      final _MockHttp inner = _MockHttp();
      final InMemoryOAuth2TokenStore store = InMemoryOAuth2TokenStore(
        OAuth2Token.nonExpiring(accessToken: 'TOK', refreshToken: 'R'),
      );
      int refreshCount = 0;
      final OAuth2HttpClient client = OAuth2HttpClient(
        inner: inner,
        store: store,
        refreshFn: (OAuth2Token _) async {
          refreshCount++;
          return OAuth2Token.nonExpiring(
            accessToken: 'NEW',
            refreshToken: 'NEW_R',
          );
        },
      );
      inner.nextResponse = _response(500, '{}');
      final RestResponse<dynamic> response = await client.execute(
        RestRequest(
          method: 'GET',
          path: '/foo',
          baseUrl: 'https://x',
          headers: const <String, String>{},
        ),
        decoder: _identityDecoder<dynamic>(),
      );
      expect(response.statusCode, 500);
      // No refresh, no retry.
      expect(refreshCount, 0);
      expect(inner.callCount, 1);
    });
  });
}

RestResponse<dynamic> _okResponse(String body) => _response(200, body);
RestResponse<dynamic> _response(int code, String body) => RestResponse<dynamic>(
      statusCode: code,
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: null,
      rawBody: body,
      request: RestRequest(
        method: 'GET',
        path: '/x',
        baseUrl: 'https://x',
        headers: const <String, String>{},
      ),
    );

/// A mock HttpClient for tests. The caller
/// pushes responses into [responses] (or
/// [nextResponse]) and the mock returns them
/// in order.
class _MockHttp implements HttpClient {
  final List<RestResponse<dynamic>> responses = <RestResponse<dynamic>>[];
  RestResponse<dynamic>? nextResponse;
  RestRequest? lastRequest;
  final List<RestRequest> requests = <RestRequest>[];
  int callCount = 0;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required dynamic decoder,
    dynamic cancelToken,
  }) async {
    callCount++;
    lastRequest = request;
    requests.add(request);
    if (nextResponse != null) {
      final RestResponse<dynamic> r = nextResponse!;
      nextResponse = null;
      return r;
    }
    if (responses.isNotEmpty) {
      return responses.removeAt(0);
    }
    return _okResponse('{}');
  }

  @override
  Future<void> close() async {}
}

Decoder<T> _identityDecoder<T>() => (dynamic data) => data as T;
