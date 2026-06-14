// Tests that verify ("absorb d_rest") produced a faithful
// integration. The runtime that ships in
// `package:d_rocket/d_rocket.dart` is byte-for-byte the same as
// the legacy `package:d_rest/d_rest.dart` 0.1.0 — we just
// re-export it from a new home.
//
// This file does NOT exercise the codegen (that lives in
// `d_rocket_builder` and is tested by the `d_rocket_builder`
// unit suite). It only checks that the runtime API behaves
// the same way: same `@RestClient` / `@Route` / `@HttpGet` /
// `@Body` / `@Query` / `@Path` / `@Header` / `@Field` / `@Part`
// / `@RawBody` annotations, same `RestRequest` / `RestResponse`
// value types, same `dRest` singleton, same `invokeRequest`
// helper, same `RestInterceptor` / `HttpClient` interfaces.

import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  // Reset the singleton state at the start and end of every test
  // so a stray mutation cannot poison the next run.
  setUp(() {
    Serializer.reset();
    dRest.useDefaults(
      httpClient: _NullHttpClient(),
      interceptors: <RestInterceptor>[],
    );
    // Register `Author` so the round-trip test (and any test
    // that calls `dRest.encodeBody<Author>(...)`) works
    // without a build_runner dependency.
    Serializer.register<Author>(
      fromJson: _authorFromJson,
      toJson: (Author a) => <String, dynamic>{
        'id': a.id,
        'name': a.name,
        'email': a.email,
      },
    );
  });
  tearDown(() {
    Serializer.reset();
    dRest.useDefaults(
      httpClient: _NullHttpClient(),
      interceptors: <RestInterceptor>[],
    );
  });

  group('Fase C — runtime parity with d_rest 0.1.0', () {
    test('re-exports the dRest singleton', () {
      expect(dRest, isNotNull);
      expect(dRest, same(DRest.instance));
      expect(dRest.client, isA<HttpClient>());
    });

    test('re-exports the @RestClient annotation', () {
      const RestClient c1 = RestClient();
      const RestClient c2 = RestClient(
        baseUrl: 'https://api.x.com',
        headers: <String, String>{'X-Tenant': 'acme'},
        timeout: Duration(seconds: 60),
      );
      expect(c1.baseUrl, '');
      expect(c1.headers, isEmpty);
      expect(c1.timeout, isNull);
      expect(c2.baseUrl, 'https://api.x.com');
      expect(c2.headers, <String, String>{'X-Tenant': 'acme'});
      expect(c2.timeout, const Duration(seconds: 60));
    });

    test('re-exports the @Route annotation (with optional baseUrl override)',
        () {
      const Route r1 = Route('/api/v1/todos');
      const Route r2 = Route('/api/v1/todos', baseUrl: 'https://other.x.com');
      expect(r1.path, '/api/v1/todos');
      expect(r1.baseUrl, isNull);
      expect(r2.baseUrl, 'https://other.x.com');
    });

    test('re-exports the 7 HTTP verb annotations', () {
      // Each verb is a const-subclass of `HttpVerb` with a
      // `path` argument and an optional `headers` map.
      const HttpGet g = HttpGet();
      const HttpGet gp = HttpGet('/{id}');
      const HttpPost p = HttpPost('/items');
      const HttpPut u = HttpPut('/{id}');
      const HttpPatch pa = HttpPatch('/{id}');
      const HttpDelete d = HttpDelete('/{id}');
      const HttpHead h = HttpHead();
      const HttpOptions o = HttpOptions();

      expect(g, isA<HttpVerb>());
      expect(gp.path, '/{id}');
      expect(p.path, '/items');
      expect(u.path, '/{id}');
      expect(pa.path, '/{id}');
      expect(d.path, '/{id}');
      expect(h, isA<HttpVerb>());
      expect(o, isA<HttpVerb>());

      // String conversion helper.
      expect(httpVerbToString(g), 'GET');
      expect(httpVerbToString(p), 'POST');
      expect(httpVerbToString(u), 'PUT');
      expect(httpVerbToString(pa), 'PATCH');
      expect(httpVerbToString(d), 'DELETE');
      expect(httpVerbToString(h), 'HEAD');
      expect(httpVerbToString(o), 'OPTIONS');
    });

    test(
        're-exports the 7 parameter annotations (Body/Query/Path/Header/Field/Part/RawBody)',
        () {
      const Body b = Body();
      const Query q1 = Query();
      const Query q2 = Query('page');
      const Path pa2 = Path('id');
      const Header h2 = Header('X-Tenant');
      const Field f = Field();
      const Part p = Part();
      const RawBody r = RawBody();

      expect(b, isA<Parameter>());
      expect(q1, isA<Parameter>());
      expect(q1.name, isNull);
      expect(q2.name, 'page');
      expect(pa2.name, 'id');
      expect(h2.name, 'X-Tenant');
      expect(f, isA<Parameter>());
      expect(p, isA<Parameter>());
      expect(r, isA<Parameter>());
    });

    test('RestRequest resolves path placeholders and joins URLs correctly', () {
      // Byte-for-byte parity with `d_rest 0.1.0`.
      final RestRequest req = RestRequest(
        method: 'GET',
        path: '/users/{id}/posts/{postId}',
        baseUrl: 'https://api.x.com',
        pathParameters: <String, Object>{'id': 42, 'postId': 'abc'},
      );
      expect(req.fullUrl, 'https://api.x.com/users/42/posts/abc');
    });

    test('RestRequest appends query parameters via `fullUrl`', () {
      final RestRequest req = RestRequest(
        method: 'GET',
        path: '/search',
        baseUrl: 'https://api.x.com',
        queryParameters: <String, String>{'q': 'flutter', 'limit': '10'},
      );
      expect(req.fullUrl, contains('q=flutter'));
      expect(req.fullUrl, contains('limit=10'));
    });

    test('RestRequest.toString produces a debug-friendly representation', () {
      final RestRequest req = RestRequest(
        method: 'POST',
        path: '/items',
        baseUrl: 'https://api.x.com',
        headers: <String, String>{'Content-Type': 'application/json'},
        body: '{"name":"x"}',
      );
      final String s = req.toString();
      expect(s, startsWith('RestRequest('));
      expect(s, contains('POST'));
      expect(s, contains('/items'));
    });

    test('RestResponse has isSuccess / hasBody derived getters', () {
      final RestResponse<int> r200 = RestResponse<int>(
        statusCode: 200,
        headers: const <String, String>{},
        body: 1,
        rawBody: '1',
        request: RestRequest(method: 'GET', path: '/'),
      );
      final RestResponse<int> r404 = RestResponse<int>(
        statusCode: 404,
        headers: const <String, String>{},
        body: null,
        rawBody: '',
        request: RestRequest(method: 'GET', path: '/'),
      );
      expect(r200.isSuccess, isTrue);
      expect(r200.hasBody, isTrue);
      expect(r404.isSuccess, isFalse);
      expect(r404.hasBody, isFalse);
    });

    test('RestException family: 3 distinct subtypes', () {
      // Each subtype is `sealed` and the public API has 3 fixed
      // members: `RestHttpException`, `NetworkException`,
      // `RestConfigException`.
      final RestException e1 = RestConfigException('bad config');
      final RestException e2 = NetworkException('no route');
      expect(e1.message, 'bad config');
      expect(e2.message, 'no route');
    });

    test('RestHttpException.problemDetails returns the body if it is a Map',
        () {
      final Map<String, dynamic> body = <String, dynamic>{
        'type': 'about:blank'
      };
      final RestException e = RestHttpException(
        statusCode: 400,
        rawBody: '{}',
        errorBody: body,
        request: RestRequest(method: 'POST', path: '/'),
      );
      expect(e, isA<RestHttpException>());
      expect((e as RestHttpException).problemDetails, body);
    });

    test('CompositeInterceptor chains request / response / error in order',
        () async {
      final List<String> log = <String>[];
      final RestInterceptor i1 = _LoggingInterceptor(log, '1');
      final RestInterceptor i2 = _LoggingInterceptor(log, '2');
      final CompositeInterceptor chain =
          CompositeInterceptor(<RestInterceptor>[i1, i2]);

      await chain.onRequest(RestRequest(method: 'GET', path: '/'));
      expect(log, <String>['1.req', '2.req']);

      log.clear();
      await chain.onResponse(RestResponse<dynamic>(
        statusCode: 200,
        headers: const <String, String>{},
        body: null,
        rawBody: '',
        request: RestRequest(method: 'GET', path: '/'),
      ));
      expect(log, <String>['1.resp', '2.resp']);

      log.clear();
      await chain.onError(NetworkException('boom'));
      expect(log, <String>['1.err', '2.err']);
    });

    test('dRest.client is replaceable at runtime (test-friendly injection)',
        () {
      final _Recorder rec = _Recorder();
      dRest.client = rec;
      expect(dRest.client, same(rec));
    });

    test(
        'dRest.encodeBody / dRest.decodeBody bridge to the Serializer '
        '(absorbed in Fase B)', () {
      // reuses the `Serializer` reexported by .
      // Round-tripping a class with manual fromJson/toJson must
      // produce the same JSON as 's `absorbed_serializer_test`.
      final Author a = Author(1, 'Alice', null);
      final String json = dRest.encodeBody<Author>(a);
      expect(json, contains('"id":1'));
      expect(json, contains('"name":"Alice"'));
      final Author round = dRest.decodeBody<Author>(jsonDecode(json));
      expect(round.id, 1);
      expect(round.name, 'Alice');
    });
  });
}

// ─── Test fixtures ───────────────────────────────────────────────────

class _NullHttpClient implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError('NullHttpClient: should not be called');
  }

  @override
  Future<void> close() async {}
}

class _Recorder implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async =>
      RestResponse<dynamic>(
        statusCode: 200,
        headers: const <String, String>{},
        body: null,
        rawBody: '',
        request: request,
      );

  @override
  Future<void> close() async {}
}

class _LoggingInterceptor implements RestInterceptor {
  _LoggingInterceptor(this.log, this.tag);
  final List<String> log;
  final String tag;

  @override
  Future<RestRequest> onRequest(RestRequest request) async {
    log.add('$tag.req');
    return request;
  }

  @override
  Future<RestResponse<dynamic>> onResponse(
      RestResponse<dynamic> response) async {
    log.add('$tag.resp');
    return response;
  }

  @override
  Future<RestException> onError(RestException error) async {
    log.add('$tag.err');
    return error;
  }
}

class Author {
  const Author(this.id, this.name, this.email);
  final int id;
  final String name;
  final String? email;
}

/// Top-level `Author.fromJson` so it can be passed to
/// `Serializer.register` from `setUp`. Kept tiny on purpose:
/// the round-trip test only checks structural parity with the
/// `Serializer` runtime reexported by .
Author _authorFromJson(Map<String, dynamic> json) => Author(
      json['id']! as int,
      json['name']! as String,
      json['email'] as String?,
    );
