import 'dart:async';

import 'realtime_delivery.dart';

/// Bounded realtime delivery queue with explicit acknowledgement.
///
/// [enqueue] applies backpressure by rejecting new messages when the number
/// of unacknowledged messages reaches [capacity]. A transport adapter can
/// listen to [deliveries] and call [ack] only after durable processing.
class RealtimeDeliveryQueue<T> {
  RealtimeDeliveryQueue({this.capacity = 100})
      : assert(capacity > 0),
        _controller = StreamController<RealtimeDelivery<T>>.broadcast();

  final int capacity;
  final StreamController<RealtimeDelivery<T>> _controller;
  final Map<String, RealtimeDelivery<T>> _pending =
      <String, RealtimeDelivery<T>>{};
  bool _closed = false;

  Stream<RealtimeDelivery<T>> get deliveries => _controller.stream;
  int get pendingCount => _pending.length;
  bool get isClosed => _closed;

  void enqueue(RealtimeDelivery<T> delivery) {
    if (_closed) throw StateError('Realtime delivery queue is closed.');
    if (_pending.containsKey(delivery.id)) {
      throw ArgumentError.value(delivery.id, 'delivery.id', 'Already queued.');
    }
    if (_pending.length >= capacity) {
      throw StateError('Realtime delivery queue capacity has been reached.');
    }
    _pending[delivery.id] = delivery;
    _controller.add(delivery);
  }

  bool ack(String id) => _pending.remove(id) != null;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    await _controller.close();
  }
}
