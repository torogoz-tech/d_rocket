//: `CircuitBreakerHttpClient` — wraps
// any [HttpClient] and applies a circuit breaker.
// After [failureThreshold] consecutive failures the
// circuit opens; subsequent requests fail immediately
// with [CircuitOpenException] until [openDuration]
// elapses, then the circuit goes half-open.

import 'dart:async';

import '../cancel_token.dart';
import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';
import 'circuit_open_exception.dart';
import 'circuit_state.dart';

class CircuitBreakerHttpClient implements HttpClient {
  CircuitBreakerHttpClient({
    required this.inner,
    this.failureThreshold = 5,
    this.openDuration = const Duration(seconds: 30),
    this.onStateChange,
  });

  final HttpClient inner;
  final int failureThreshold;
  final Duration openDuration;
  final void Function(CircuitState state)? onStateChange;

  CircuitState _state = CircuitState.closed;
  int _consecutiveFailures = 0;
  DateTime? _openedAt;

  CircuitState get state => _state;
  int get consecutiveFailures => _consecutiveFailures;

  void _setState(CircuitState newState) {
    if (_state == newState) return;
    _state = newState;
    onStateChange?.call(newState);
  }

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    if (_state == CircuitState.open) {
      final DateTime? openedAt = _openedAt;
      if (openedAt != null &&
          DateTime.now().difference(openedAt) >= openDuration) {
        _setState(CircuitState.halfOpen);
      } else {
        throw const CircuitOpenException(
          'Circuit is open — request rejected immediately.',
        );
      }
    }
    try {
      final RestResponse<dynamic> response = await inner.execute(request,
          decoder: decoder, cancelToken: cancelToken);
      _consecutiveFailures = 0;
      _setState(CircuitState.closed);
      return response;
    } catch (e) {
      _consecutiveFailures++;
      if (_state == CircuitState.halfOpen) {
        _openedAt = DateTime.now();
        _setState(CircuitState.open);
      } else if (_consecutiveFailures >= failureThreshold) {
        _openedAt = DateTime.now();
        _setState(CircuitState.open);
      }
      rethrow;
    }
  }

  @override
  Future<void> close() async {
    await inner.close();
  }
}
