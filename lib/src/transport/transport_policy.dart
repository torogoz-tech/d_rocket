import 'dart:async';

import 'transport_request_context.dart';
import 'transport_response_context.dart';
import 'transport_response_decision.dart';

typedef TransportRequestHandler = FutureOr<TransportRequestContext> Function(
  TransportRequestContext context,
);

typedef TransportResponseHandler = FutureOr<TransportResponseDecision> Function(
  TransportResponseContext context,
);

/// Shared request/response policy hooks for transport adapters.
class TransportPolicy {
  const TransportPolicy({this.onRequest, this.onResponse});

  final TransportRequestHandler? onRequest;
  final TransportResponseHandler? onResponse;

  Future<TransportRequestContext> prepareRequest(
    TransportRequestContext context,
  ) async {
    final TransportRequestHandler? handler = onRequest;
    return handler == null ? context : await handler(context);
  }

  Future<TransportResponseDecision> processResponse(
    TransportResponseContext context,
  ) async {
    final TransportResponseHandler? handler = onResponse;
    return handler == null
        ? const TransportResponseDecision.accept()
        : await handler(context);
  }
}
