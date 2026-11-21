import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/stream_policy_http_client.dart';
import '../support/redirecting_stream_http_client.dart';

void main() {
  test('applies the shared policy to a streaming download', () async {
    final List<TransportRequestContext> requests = <TransportRequestContext>[];
    final StreamPolicyHttpClient inner = StreamPolicyHttpClient();
    final TransportStreamingClient client = TransportStreamingClient(
      httpClient: inner,
      policy: TransportPolicy(
        onRequest: (TransportRequestContext context) {
          requests.add(context);
          return context.copyWith(
            headers: <String, String>{...context.headers, 'DPoP': 'proof-1'},
          );
        },
      ),
    );

    final http.StreamedResponse response = await client.send(
      http.Request('GET', Uri.parse('https://cdn.example.test/file.zip')),
    );
    final String body = await response.stream.bytesToString();

    expect(body, 'downloaded');
    expect(requests.single.uri.toString(), 'https://cdn.example.test/file.zip');
    expect(inner.requests.single.headers['DPoP'], 'proof-1');
    client.close();
  });

  test('replays a download request for a bounded policy repeat', () async {
    int responses = 0;
    final StreamPolicyHttpClient inner = StreamPolicyHttpClient();
    final TransportStreamingClient client = TransportStreamingClient(
      httpClient: inner,
      maxAttempts: 2,
      policy: TransportPolicy(
        onResponse: (TransportResponseContext context) {
          responses++;
          return context.attempt == 1
              ? const TransportResponseDecision.retry()
              : const TransportResponseDecision.accept();
        },
      ),
    );

    final http.StreamedResponse response = await client.send(
      http.Request('GET', Uri.parse('https://cdn.example.test/file.zip')),
    );
    expect(await response.stream.transform(utf8.decoder).join(), 'downloaded');
    expect(responses, 2);
    expect(inner.requests, hasLength(2));
    client.close();
  });

  test('strips credentials before following a cross-origin download redirect',
      () async {
    final List<TransportRequestContext> policyRequests =
        <TransportRequestContext>[];
    final RedirectingStreamHttpClient inner = RedirectingStreamHttpClient(
      <http.StreamedResponse>[
        http.StreamedResponse(
          const Stream<List<int>>.empty(),
          302,
          headers: const <String, String>{
            'location': 'https://cdn.example.test/file.zip',
          },
        ),
        http.StreamedResponse(
          Stream<List<int>>.value(<int>[1, 2, 3]),
          200,
        ),
      ],
    );
    final TransportStreamingClient client = TransportStreamingClient(
      httpClient: inner,
      policy: TransportPolicy(
        onRequest: (TransportRequestContext context) {
          policyRequests.add(context);
          return context.copyWith(
            headers: <String, String>{...context.headers, 'DPoP': 'fresh'},
          );
        },
      ),
    );

    final http.StreamedResponse response = await client.send(
      http.Request('GET', Uri.parse('https://api.example.test/file.zip'))
        ..headers['Authorization'] = 'Bearer secret'
        ..headers['DPoP'] = 'proof',
    );

    expect(response.statusCode, 200);
    expect(inner.requests, hasLength(2));
    expect(inner.requests.last.headers.containsKey('Authorization'), isFalse);
    expect(inner.requests.last.headers['DPoP'], 'fresh');
    expect(inner.requests.last.url.host, 'cdn.example.test');
    expect(policyRequests.last.uri.host, 'cdn.example.test');
    client.close();
  });
}
