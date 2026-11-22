/// An outbound realtime payload waiting for transport acknowledgement.
class RealtimeOutboundMessage<T> {
  const RealtimeOutboundMessage({
    required this.id,
    required this.payload,
    this.attempt = 0,
  });

  final String id;
  final T payload;
  final int attempt;

  /// Creates the next delivery attempt for this payload.
  RealtimeOutboundMessage<T> retry() => RealtimeOutboundMessage<T>(
        id: id,
        payload: payload,
        attempt: attempt + 1,
      );
}
