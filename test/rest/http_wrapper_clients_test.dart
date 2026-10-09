import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../support/request_capture_http_client.dart';

void main() {
  test('GzipHttpClient compresses request bodies and marks the headers',
      () async {
    final RequestCaptureHttpClient inner = _capture();
    final GzipHttpClient client = GzipHttpClient(inner: inner);

    await client.execute(
      const RestRequest(
        method: 'POST',
        path: '/events',
        body: '{"ok":true}',
      ),
      decoder: (dynamic value) => value,
    );

    expect(inner.lastRequest!.headers['Content-Encoding'], 'gzip');
    expect(inner.lastRequest!.headers['Accept-Encoding'], 'gzip');
    expect(
      utf8.decode(GzipCodec.decode(inner.lastRequest!.body! as List<int>)),
      '{"ok":true}',
    );
  });

  test('HmacSignedHttpClient signs the resolved request', () async {
    final RequestCaptureHttpClient inner = _capture();
    final HmacSha256Signer signer = HmacSha256Signer(utf8.encode('secret'));
    final HmacSignedHttpClient client = HmacSignedHttpClient(
      inner: inner,
      signer: signer,
      clock: () => DateTime.utc(2026, 10, 8, 12),
    );

    await client.execute(
      const RestRequest(
        method: 'POST',
        baseUrl: 'https://example.test',
        path: '/events',
        body: '{"ok":true}',
      ),
      decoder: (dynamic value) => value,
    );

    final String timestamp =
        inner.lastRequest!.headers['X-Signature-Timestamp']!;
    final String expected = signer.signRequest(
      method: 'POST',
      url: 'https://example.test/events',
      body: utf8.encode('{"ok":true}'),
      timestamp: timestamp,
    );
    expect(inner.lastRequest!.headers['X-Signature'], expected);
  });

  test('EtagCacheHttpClient serves fresh GET responses from the cache',
      () async {
    final RequestCaptureHttpClient inner = _capture(
      headers: const <String, String>{'ETag': 'event-v1'},
    );
    final EtagCacheHttpClient client = EtagCacheHttpClient(
      inner: inner,
      maxAge: const Duration(hours: 1),
    );
    const RestRequest request = RestRequest(method: 'GET', path: '/events');

    await client.execute(request, decoder: (dynamic value) => value);
    await client.execute(request, decoder: (dynamic value) => value);

    expect(inner.calls, 1);
  });
}

RequestCaptureHttpClient _capture({Map<String, String> headers = const {}}) {
  return RequestCaptureHttpClient(
    RestResponse<dynamic>(
      statusCode: 200,
      headers: headers,
      body: <String, Object?>{'ok': true},
      rawBody: '{"ok":true}',
      request: const RestRequest(method: 'GET', path: '/events'),
    ),
  );
}
