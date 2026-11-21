import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}

class _HeaderInterceptor extends SseInterceptor {
  bool responseSeen = false;

  @override
  Future<http.BaseRequest> onRequest(http.BaseRequest request) async {
    request.headers['X-Interceptor'] = 'enabled';
    return request;
  }

  @override
  Future<http.StreamedResponse> onResponse(
    http.StreamedResponse response,
  ) async {
    responseSeen = true;
    return response;
  }
}

void main() {
  test('configures default headers and interceptors on the SSE client',
      () async {
    final List<http.BaseRequest> requests = <http.BaseRequest>[];
    final _HeaderInterceptor interceptor = _HeaderInterceptor();
    final _StreamingClient transport =
        _StreamingClient((http.BaseRequest request) async {
      requests.add(request);
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('data: ready\n\n')),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      );
    });
    final HttpSseClient client = HttpSseClient(
      httpClient: transport,
      defaultHeaders: <String, String>{'X-Default': 'enabled'},
      interceptors: <SseInterceptor>[interceptor],
    );

    final List<SseEvent> events = await client
        .connect(
          Uri.parse('https://example.test/events'),
          headers: <String, String>{'X-Call': 'enabled'},
          lastEventId: 'cursor-7',
        )
        .toList();

    expect(events.single.data, 'ready');
    expect(requests.single.headers['X-Default'], 'enabled');
    expect(requests.single.headers['X-Call'], 'enabled');
    expect(requests.single.headers['X-Interceptor'], 'enabled');
    expect(requests.single.headers['Last-Event-ID'], 'cursor-7');
    expect(interceptor.responseSeen, isTrue);
    await client.close();
  });

  test('rejects a successful response that is not an SSE stream', () async {
    final _StreamingClient transport =
        _StreamingClient((http.BaseRequest request) async {
      return http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('{"ok":true}')),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    final HttpSseClient client = HttpSseClient(httpClient: transport);

    await expectLater(
      client.connect(Uri.parse('https://example.test/events')).toList(),
      throwsA(isA<FormatException>()),
    );
    await client.close();
  });

  test('close completes when the SSE stream has not been listened to',
      () async {
    final Completer<http.StreamedResponse> response =
        Completer<http.StreamedResponse>();
    final _StreamingClient transport =
        _StreamingClient((http.BaseRequest request) {
      return response.future;
    });
    final HttpSseClient client = HttpSseClient(httpClient: transport);

    client.connect(Uri.parse('https://example.test/events'));

    await expectLater(client.close(), completes);
    response.complete(
      http.StreamedResponse(
        const Stream<List<int>>.empty(),
        200,
        headers: <String, String>{'content-type': 'text/event-stream'},
      ),
    );
  });
}
