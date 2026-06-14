//: the exception thrown by
// [CircuitBreakerHttpClient] when the circuit is
// open. NOT a [RestException] (it can fire without
// an HTTP request even being attempted).

class CircuitOpenException implements Exception {
  const CircuitOpenException(this.message);

  final String message;

  @override
  String toString() => 'CircuitOpenException: $message';
}
