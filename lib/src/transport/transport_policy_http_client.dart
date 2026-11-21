import '../rest/client/http_client.dart';
import '../rest/rest_request.dart';
import '../rest/rest_response.dart';
import '../rest/decoder.dart';
import '../rest/cancel_token.dart';
import 'transport_policy.dart';
import 'transport_request_context.dart';
import 'transport_response_context.dart';
import 'transport_response_decision.dart';

/// Applies a [TransportPolicy] around an existing REST client.
class TransportPolicyHttpClient implements HttpClient {
  TransportPolicyHttpClient({
    required this.inner,
    required this.policy,
    this.maxAttempts = 1,
  }) : assert(maxAttempts > 0);

  final HttpClient inner;
  final TransportPolicy policy;
  final int maxAttempts;

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    RestRequest current = request;
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      final TransportRequestContext prepared =
          await policy.prepareRequest(_requestContext(current, attempt));
      current = _applyContext(current, prepared);
      final RestResponse<dynamic> response = await inner.execute(
        current,
        decoder: decoder,
        cancelToken: cancelToken,
      );
      final TransportResponseDecision decision = await policy.processResponse(
        TransportResponseContext(
          method: current.method,
          uri: Uri.parse(current.fullUrl),
          statusCode: response.statusCode,
          headers: response.headers,
          body: response.body,
          attempt: attempt,
        ),
      );
      if (!decision.retry || attempt == maxAttempts) {
        return response;
      }
      if (decision.delay > Duration.zero) {
        await Future<void>.delayed(decision.delay);
      }
    }
    throw StateError('Transport policy exhausted without a response');
  }

  @override
  Future<void> close() => inner.close();

  TransportRequestContext _requestContext(RestRequest request, int attempt) {
    return TransportRequestContext(
      method: request.method,
      uri: Uri.parse(request.fullUrl),
      headers: request.headers,
      body: request.body,
      attempt: attempt,
    );
  }

  RestRequest _applyContext(
    RestRequest original,
    TransportRequestContext context,
  ) {
    return original.copyWith(
      baseUrl: context.uri.toString(),
      path: '',
      headers: context.headers,
      body: context.body,
      queryParameters: const <String, String>{},
      pathParameters: const <String, Object>{},
    );
  }
}
