/// Signals to a reconnecting stream that a transport policy requested a retry.
class TransportRetryException implements Exception {
  const TransportRetryException(this.statusCode);

  final int statusCode;

  @override
  String toString() => 'TransportRetryException(statusCode: $statusCode)';
}
