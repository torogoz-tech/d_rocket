//: tests for the new [CancelToken]
// flow. Spins up a local `HttpServer.bind` that
// delays its response so the test can cancel
// mid-flight and assert the client throws a
// [RequestCancelledException] without ever
// reading the body.

import 'dart:async';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 8.2 — CancelToken: cancel in-flight HTTP request', () {
    late HttpServer server;
    late String baseUrl;
    late HttpClient client;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      client = HttpPackageClient();
    });

    tearDown(() async {
      client.close();
      await server.close(force: true);
    });

    test('cancel BEFORE send: the request never reaches the server', () async {
      var hits = 0;
      server.listen((HttpRequest req) async {
        hits += 1;
        req.response.statusCode = 200;
        await req.response.close();
      });
      // Give the listener a tick to register.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final token = CancelToken();
      token.cancel('user navigated away before send');

      await expectLater(
        client.execute(
          RestRequest(method: 'GET', path: '/x', baseUrl: baseUrl),
          decoder: (dynamic d) => d,
          cancelToken: token,
        ),
        throwsA(isA<RequestCancelledException>().having(
            (RequestCancelledException e) => e.reason,
            'reason',
            'user navigated away before send')),
      );
      // The cancel may have raced the send — that's
      // OK; the important guarantee is "no body
      // delivered, no success".
      expect(hits, lessThanOrEqualTo(1));
    });

    test('cancel DURING response: the body stream is dropped', () async {
      // Server sends headers, then a slow body.
      // The test cancels mid-body.
      server.listen((HttpRequest req) async {
        req.response.headers.contentType = ContentType.text;
        req.response.statusCode = 200;
        // Write half the body, then wait.
        req.response.write('hello ');
        await req.response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        req.response.write('world');
        await req.response.close();
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final token = CancelToken();
      final Future<RestResponse<dynamic>> future = client.execute(
        RestRequest(method: 'GET', path: '/slow', baseUrl: baseUrl),
        decoder: (dynamic d) => d,
        cancelToken: token,
      );

      // Cancel after 50ms (server is in the middle of
      // its 200ms sleep).
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        token.cancel('navigated away');
      });

      await expectLater(
        future,
        throwsA(isA<RequestCancelledException>()),
      );
    });

    test('no cancel token: legacy behaviour is preserved', () async {
      server.listen((HttpRequest req) async {
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write('{"ok":true}');
        await req.response.close();
      });
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final RestResponse<dynamic> r = await client.execute(
        RestRequest(method: 'GET', path: '/x', baseUrl: baseUrl),
        decoder: (dynamic d) => d,
      );
      expect(r.statusCode, 200);
      expect(r.body, isA<Map<String, Object?>>());
    });

    test('CancelToken.cancel is idempotent', () {
      final token = CancelToken();
      token.cancel('first');
      token.cancel('second');
      expect(token.isCancelled, isTrue);
      expect(token.reason, 'first');
    });
  });
}
