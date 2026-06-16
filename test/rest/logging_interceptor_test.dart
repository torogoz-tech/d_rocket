// Tests for the boxed LoggingInterceptor.
//
// The contract being tested is the shape of the log
// line, the opt-in flags, and the integration with
// redactPragmaKey. No HTTP is performed; the
// RestRequest / RestResponse / RestException are
// built directly from their const constructors.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('LoggingInterceptor — default (no bodies, no headers)', () {
    test('onRequest logs method + URL with an arrow prefix', () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(log: lines.add);
      const RestRequest req = RestRequest(
        method: 'GET',
        path: '/api/v1/todos',
      );
      await i.onRequest(req);
      expect(lines, hasLength(1));
      expect(lines.first, '→ GET /api/v1/todos');
    });

    test('onResponse logs status + method + URL with a left-arrow prefix',
        () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(log: lines.add);
      const RestRequest req = RestRequest(method: 'POST', path: '/items');
      final RestResponse<dynamic> resp = RestResponse<dynamic>(
        statusCode: 201,
        rawBody: '',
        request: req,
        headers: const <String, String>{},
      );
      await i.onResponse(resp);
      expect(lines.first, '← 201 POST /items');
    });

    test('onError logs exception type, message, and (status method url)',
        () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(log: lines.add);
      const RestRequest req = RestRequest(method: 'DELETE', path: '/x/1');
      final RestException err = RestHttpException(
        statusCode: 404,
        request: req,
      );
      await i.onError(err);
      expect(lines, hasLength(1));
      expect(
        lines.first,
        contains('× RestHttpException HTTP 404 (404 DELETE /x/1)'),
      );
    });
  });

  group('LoggingInterceptor — includeBodies + redactPragmaKey', () {
    test('logs body verbatim when the redactor is an identity function',
        () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(
        log: lines.add,
        includeBodies: true,
        redactBody: (String s) => s,
      );
      const RestRequest req = RestRequest(
        method: 'POST',
        path: '/sql',
        body: "PRAGMA key = 'hunter2'",
      );
      await i.onRequest(req);
      expect(
        lines.first,
        "→ POST /sql body=PRAGMA key = 'hunter2'",
      );
    });

    test('redacts PRAGMA key in request body by default', () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(
        log: lines.add,
        includeBodies: true,
      );
      const RestRequest req = RestRequest(
        method: 'POST',
        path: '/sql',
        body: "PRAGMA key = 'hunter2'",
      );
      await i.onRequest(req);
      expect(
        lines.first,
        "→ POST /sql body=PRAGMA key = '***'",
      );
    });

    test('redacts PRAGMA rekey in response body by default', () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(
        log: lines.add,
        includeBodies: true,
      );
      const RestRequest req = RestRequest(method: 'POST', path: '/sql');
      final RestResponse<dynamic> resp = RestResponse<dynamic>(
        statusCode: 200,
        rawBody: "PRAGMA rekey = 'O''Brien'",
        request: req,
        headers: const <String, String>{},
      );
      await i.onResponse(resp);
      expect(
        lines.first,
        "← 200 POST /sql body=PRAGMA rekey = '***'",
      );
    });

    test('accepts a custom redactor', () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(
        log: lines.add,
        includeBodies: true,
        redactBody: (String s) => s.replaceAll('Bearer SECRET', 'Bearer ***'),
      );
      const RestRequest req = RestRequest(
        method: 'GET',
        path: '/me',
        body: 'Authorization: Bearer SECRET',
      );
      await i.onRequest(req);
      expect(
        lines.first,
        '→ GET /me body=Authorization: Bearer ***',
      );
    });
  });

  group('LoggingInterceptor — includeHeaders', () {
    test('appends headers when enabled', () async {
      final List<String> lines = <String>[];
      final LoggingInterceptor i = LoggingInterceptor(
        log: lines.add,
        includeHeaders: true,
      );
      const RestRequest req = RestRequest(
        method: 'GET',
        path: '/x',
        headers: <String, String>{'X-Trace': 'abc'},
      );
      await i.onRequest(req);
      expect(
        lines.first,
        '→ GET /x headers={X-Trace: abc}',
      );
    });
  });

  group('LoggingInterceptor — composes with CompositeInterceptor', () {
    test('returns the same request object (pass-through)', () async {
      final LoggingInterceptor i = LoggingInterceptor(log: (_) {});
      const RestRequest req = RestRequest(method: 'GET', path: '/p');
      final RestRequest out = await i.onRequest(req);
      expect(identical(out, req), isTrue);
    });

    test('returns the same response object (pass-through)', () async {
      final LoggingInterceptor i = LoggingInterceptor(log: (_) {});
      const RestRequest req = RestRequest(method: 'GET', path: '/p');
      final RestResponse<dynamic> resp = RestResponse<dynamic>(
        statusCode: 200,
        rawBody: '',
        request: req,
        headers: const <String, String>{},
      );
      final RestResponse<dynamic> out = await i.onResponse(resp);
      expect(identical(out, resp), isTrue);
    });

    test('returns the same error object (pass-through)', () async {
      final LoggingInterceptor i = LoggingInterceptor(log: (_) {});
      const RestRequest req = RestRequest(method: 'GET', path: '/p');
      final RestException err = RestHttpException(
        statusCode: 500,
        request: req,
      );
      final RestException out = await i.onError(err);
      expect(identical(out, err), isTrue);
    });
  });
}
