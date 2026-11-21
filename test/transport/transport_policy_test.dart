import 'package:d_rocket/d_rocket.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/policy_http_client.dart';

void main() {
  test('policy receives final URI and can add per-attempt headers', () async {
    final List<TransportRequestContext> requests = <TransportRequestContext>[];
    final TransportPolicy policy = TransportPolicy(
      onRequest: (TransportRequestContext context) {
        requests.add(context);
        return context.copyWith(
          headers: <String, String>{
            ...context.headers,
            'X-Attempt': '${context.attempt}',
          },
        );
      },
    );
    final PolicyHttpClient inner = PolicyHttpClient();
    final TransportPolicyHttpClient client = TransportPolicyHttpClient(
      inner: inner,
      policy: policy,
    );

    await client.execute(
      const RestRequest(
        method: 'GET',
        baseUrl: 'https://api.example.test/v1',
        path: '/vehicles/{id}',
        pathParameters: <String, Object>{'id': 'vehicle 1'},
        queryParameters: <String, String>{'include': 'owner'},
      ),
      decoder: (dynamic body) => body,
    );

    expect(requests.single.uri.toString(),
        'https://api.example.test/v1/vehicles/vehicle%201?include=owner');
    expect(inner.lastRequest?.headers['X-Attempt'], '1');
  });

  test('cross-origin redirects strip credential headers', () {
    final TransportRequestContext context = TransportRequestContext(
      method: 'GET',
      uri: Uri.parse('https://api.example.test/events'),
      headers: const <String, String>{
        'Authorization': 'Bearer secret',
        'DPoP': 'proof',
        'Cookie': 'session=secret',
        'X-Trace': 'trace',
      },
      attempt: 1,
    );

    final TransportRequestContext redirected = context.forRedirect(
      Uri.parse('https://cdn.example.test/events'),
    );

    expect(redirected.headers, <String, String>{'X-Trace': 'trace'});
    expect(redirected.uri.host, 'cdn.example.test');
  });

  test('response policy can request a bounded repeat', () async {
    final List<TransportResponseContext> responses =
        <TransportResponseContext>[];
    final TransportPolicy policy = TransportPolicy(
      onResponse: (TransportResponseContext context) {
        responses.add(context);
        return context.attempt == 1
            ? const TransportResponseDecision.retry()
            : const TransportResponseDecision.accept();
      },
    );
    final PolicyHttpClient inner = PolicyHttpClient();
    final TransportPolicyHttpClient client = TransportPolicyHttpClient(
      inner: inner,
      policy: policy,
      maxAttempts: 2,
    );

    await client.execute(
      const RestRequest(
        method: 'GET',
        baseUrl: 'https://api.example.test',
        path: '/retry',
      ),
      decoder: (dynamic body) => body,
    );

    expect(responses.map((TransportResponseContext item) => item.attempt),
        <int>[1, 2]);
    expect(inner.requests, hasLength(2));
  });

  test('SSE adapter applies the same request policy', () async {
    final TransportPolicy policy = TransportPolicy(
      onRequest: (TransportRequestContext context) => context.copyWith(
        headers: <String, String>{...context.headers, 'DPoP': 'fresh-proof'},
      ),
    );
    final http.Request request = http.Request(
      'GET',
      Uri.parse('https://api.example.test/events'),
    );

    final http.BaseRequest result =
        await TransportPolicySseInterceptor(policy).onRequest(request);

    expect(result.headers['DPoP'], 'fresh-proof');
  });
}
