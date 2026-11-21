import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/sse_ownership_transport.dart';

void main() {
  test('closes an explicitly owned injected transport and is idempotent',
      () async {
    final SseOwnershipTransport transport = SseOwnershipTransport();
    final HttpSseClient client = HttpSseClient(
      httpClient: transport,
      ownsHttpClient: true,
    );

    await client.connect(Uri.parse('https://api.example.test/events')).toList();
    await client.close();
    await client.close();

    expect(transport.closed, isTrue);
  });

  test('keeps a shared injected transport open', () async {
    final SseOwnershipTransport transport = SseOwnershipTransport();
    final HttpSseClient client = HttpSseClient(
      httpClient: transport,
      ownsHttpClient: false,
    );

    await client.connect(Uri.parse('https://api.example.test/events')).toList();
    await client.close();

    expect(transport.closed, isFalse);
  });

  test('closes an owned transport while a connection is pending', () async {
    final Completer<http.StreamedResponse> pending =
        Completer<http.StreamedResponse>();
    final SseOwnershipTransport transport = SseOwnershipTransport(
      pendingResponse: pending,
    );
    final HttpSseClient client = HttpSseClient(
      httpClient: transport,
      ownsHttpClient: true,
    );

    client.connect(Uri.parse('https://api.example.test/events'));
    await client.close();

    expect(transport.closed, isTrue);
    pending.complete(
      http.StreamedResponse(
        Stream<List<int>>.value(utf8.encode('data: ignored\n\n')),
        200,
        headers: const <String, String>{'content-type': 'text/event-stream'},
      ),
    );
  });
}
