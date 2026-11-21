import 'package:http/http.dart' as http;

import 'transport_policy.dart';
import 'transport_request_context.dart';
import 'transport_response_context.dart';
import 'transport_response_decision.dart';

/// Applies a shared [TransportPolicy] to streaming HTTP downloads.
class TransportStreamingClient extends http.BaseClient {
  TransportStreamingClient({
    http.Client? httpClient,
    required this.policy,
    this.maxAttempts = 1,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        assert(maxAttempts > 0);

  final http.Client _httpClient;
  final TransportPolicy policy;
  final int maxAttempts;
  final bool _ownsHttpClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    http.BaseRequest current = request;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      TransportRequestContext prepared = await policy.prepareRequest(
        TransportRequestContext(
          method: current.method,
          uri: current.url,
          headers: current.headers,
          body: current is http.Request ? current.bodyBytes : null,
          attempt: attempt,
        ),
      );
      late http.StreamedResponse response;
      for (int redirect = 0; redirect <= 5; redirect++) {
        current = _copyRequest(current, prepared);
        response = await _httpClient.send(current);
        final String? location = response.headers['location'];
        if (location == null || !_isRedirect(response.statusCode)) break;
        if (redirect == 5) {
          await response.stream.drain<void>();
          throw StateError('Streaming transport exceeded redirect limit');
        }
        await response.stream.drain<void>();
        final TransportRequestContext redirected = prepared.forRedirect(
          prepared.uri.resolve(location),
        );
        prepared = await policy.prepareRequest(redirected);
      }
      final TransportResponseDecision decision = await policy.processResponse(
        TransportResponseContext(
          method: current.method,
          uri: current.url,
          statusCode: response.statusCode,
          headers: response.headers,
          attempt: attempt,
        ),
      );
      if (!decision.retry || attempt == maxAttempts) return response;
      await response.stream.drain<void>();
      if (decision.delay > Duration.zero) {
        await Future<void>.delayed(decision.delay);
      }
    }
    throw StateError('Transport policy exhausted without a response');
  }

  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  http.BaseRequest _copyRequest(
    http.BaseRequest original,
    TransportRequestContext context,
  ) {
    if (original is! http.Request) {
      if (context.uri != original.url ||
          context.headers.length != original.headers.length) {
        throw StateError(
          'Streaming retries require an http.Request with a replayable body',
        );
      }
      return original;
    }
    return http.Request(original.method, context.uri)
      // Redirects are followed here so cross-origin credentials can be
      // removed through TransportRequestContext.forRedirect first.
      ..followRedirects = false
      ..maxRedirects = original.maxRedirects
      ..persistentConnection = original.persistentConnection
      ..headers.addAll(context.headers)
      ..bodyBytes = original.bodyBytes;
  }

  bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}
