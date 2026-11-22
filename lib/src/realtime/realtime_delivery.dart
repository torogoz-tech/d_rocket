/// A queued realtime payload that must be acknowledged by its consumer.
class RealtimeDelivery<T> {
  const RealtimeDelivery({required this.id, required this.payload});

  final String id;
  final T payload;
}
