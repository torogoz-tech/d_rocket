//: the 3 states of the circuit breaker
// state machine. See `circuit_breaker_http_client.dart`
// for the state transitions.

enum CircuitState {
  /// Closed: requests flow through normally.
  closed,

  /// Open: all requests fail immediately with
  /// [CircuitOpenException].
  open,

  /// Half-open: the next request is allowed through
  /// to test the waters. If it succeeds, the circuit
  /// closes. If it fails, the circuit opens again.
  halfOpen,
}
