//: tests for the SSE client. Uses
// a real `HttpServer.bind` to serve a
// `text/event-stream` response and verify the
// parser handles all the wire-format corners.

import 'dart:async';
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 6.2 — SseEvent: shape', () {
    test('an event has data + optional event/id/retry', () {
      const SseEvent ev = SseEvent(
        data: 'hello',
        event: 'greeting',
        id: '42',
        retry: Duration(milliseconds: 5000),
      );
      expect(ev.data, 'hello');
      expect(ev.event, 'greeting');
      expect(ev.id, '42');
      expect(ev.retry, const Duration(milliseconds: 5000));
    });
  });

  group('Fase 6.2 — HttpSseClient: real server', () {
    late HttpServer server;
    late Uri serverUri;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      serverUri = Uri.parse('http://127.0.0.1:${server.port}');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    Future<void> serveFor(
      void Function(HttpResponse response) write,
    ) async {
      server.listen((HttpRequest request) async {
        // Only handle /events.
        if (request.uri.path != '/events') {
          request.response.statusCode = 404;
          await request.response.close();
          return;
        }
        request.response.headers.contentType =
            ContentType('text', 'event-stream');
        request.response.headers.add('Cache-Control', 'no-cache');
        request.response.headers.add('Connection', 'keep-alive');
        // Important: do NOT set Content-Length
        // (chunked transfer is implied by the
        // lack of a length).
        write(request.response);
        await request.response.close();
      });
    }

    test('a single data-only event is parsed correctly', () async {
      await serveFor((HttpResponse r) async {
        r.write('data: hello\n\n');
      });
      final HttpSseClient client = HttpSseClient();
      final List<SseEvent> got =
          await client.connect(Uri.parse('$serverUri/events')).toList();
      expect(got, hasLength(1));
      expect(got.first.data, 'hello');
      expect(got.first.event, isNull);
      expect(got.first.id, isNull);
    });

    test('event + id + retry are parsed', () async {
      await serveFor((HttpResponse r) async {
        r.write('event: greeting\n');
        r.write('id: 42\n');
        r.write('retry: 5000\n');
        r.write('data: hello\n\n');
      });
      final HttpSseClient client = HttpSseClient();
      final List<SseEvent> got =
          await client.connect(Uri.parse('$serverUri/events')).toList();
      expect(got, hasLength(1));
      expect(got.first.event, 'greeting');
      expect(got.first.id, '42');
      expect(got.first.retry, const Duration(milliseconds: 5000));
      expect(got.first.data, 'hello');
    });

    test('multi-line data is joined with \\n', () async {
      await serveFor((HttpResponse r) async {
        r.write('data: line 1\n');
        r.write('data: line 2\n');
        r.write('data: line 3\n\n');
      });
      final HttpSseClient client = HttpSseClient();
      final List<SseEvent> got =
          await client.connect(Uri.parse('$serverUri/events')).toList();
      expect(got, hasLength(1));
      expect(got.first.data, 'line 1\nline 2\nline 3');
    });

    test('multiple events in one stream are emitted as multiple events',
        () async {
      await serveFor((HttpResponse r) async {
        r.write('data: first\n\n');
        r.write('data: second\n\n');
        r.write('data: third\n\n');
      });
      final HttpSseClient client = HttpSseClient();
      final List<SseEvent> got =
          await client.connect(Uri.parse('$serverUri/events')).toList();
      expect(got, hasLength(3));
      expect(got[0].data, 'first');
      expect(got[1].data, 'second');
      expect(got[2].data, 'third');
    });

    test('comment lines (starting with ":") are ignored', () async {
      await serveFor((HttpResponse r) async {
        r.write(': this is a comment\n');
        r.write('data: hello\n\n');
      });
      final HttpSseClient client = HttpSseClient();
      final List<SseEvent> got =
          await client.connect(Uri.parse('$serverUri/events')).toList();
      expect(got, hasLength(1));
      expect(got.first.data, 'hello');
    });

    test('a non-200 response surfaces an error to the stream', () async {
      server.listen((HttpRequest request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });
      final HttpSseClient client = HttpSseClient();
      final Stream<SseEvent> stream =
          client.connect(Uri.parse('$serverUri/events'));
      // The stream completes with an error.
      await expectLater(
        stream.toList(),
        throwsA(isA<StateError>()),
      );
    });
  });
}
