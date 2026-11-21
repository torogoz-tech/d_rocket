import 'package:http/http.dart' as http;

import '../realtime/sse_interceptor.dart';
import 'transport_policy.dart';
import 'transport_request_context.dart';
import 'transport_response_context.dart';
import 'transport_response_decision.dart';
import 'transport_retry_exception.dart';

/// Adapts a [TransportPolicy] to the SSE interceptor lifecycle.
class TransportPolicySseInterceptor extends SseInterceptor {
  TransportPolicySseInterceptor(this.policy);

  final TransportPolicy policy;

  @override
  Future<http.BaseRequest> onRequest(http.BaseRequest request) async {
    final TransportRequestContext context = await policy.prepareRequest(
      TransportRequestContext(
        method: request.method,
        uri: request.url,
        headers: request.headers,
        body: request is http.Request ? request.body : null,
        attempt: 1,
      ),
    );
    if (request is http.Request) {
      final http.Request transformed = http.Request(
        context.method,
        context.uri,
      )
        ..followRedirects = request.followRedirects
        ..maxRedirects = request.maxRedirects
        ..persistentConnection = request.persistentConnection
        ..headers.addAll(context.headers)
        ..body = request.body;
      return transformed;
    }
    if (request.url != context.uri) {
      throw StateError(
        'TransportPolicy cannot replace the URI of a streamed SSE request.',
      );
    }
    request.headers
      ..clear()
      ..addAll(context.headers);
    return request;
  }

  @override
  Future<http.StreamedResponse> onResponse(
    http.StreamedResponse response,
  ) async {
    final TransportResponseDecision decision = await policy.processResponse(
      TransportResponseContext(
        method: response.request?.method ?? 'GET',
        uri: response.request?.url ?? Uri.parse('about:blank'),
        statusCode: response.statusCode,
        headers: response.headers,
        attempt: 1,
      ),
    );
    if (decision.retry) {
      throw TransportRetryException(response.statusCode);
    }
    return response;
  }
}
