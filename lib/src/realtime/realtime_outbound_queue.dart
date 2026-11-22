import 'dart:async';

import 'realtime_outbound_message.dart';

/// Bounded outbound queue with explicit acknowledgement and retry policy.
class RealtimeOutboundQueue<T> {
  RealtimeOutboundQueue({this.capacity = 100, this.maxAttempts = 3})
      : assert(capacity > 0),
        assert(maxAttempts > 0),
        _controller = StreamController<RealtimeOutboundMessage<T>>.broadcast();

  final int capacity;
  final int maxAttempts;
  final StreamController<RealtimeOutboundMessage<T>> _controller;
  final Map<String, RealtimeOutboundMessage<T>> _pending =
      <String, RealtimeOutboundMessage<T>>{};
  bool _closed = false;

  Stream<RealtimeOutboundMessage<T>> get messages => _controller.stream;
  int get pendingCount => _pending.length;
  bool get isClosed => _closed;

  RealtimeOutboundMessage<T> enqueue(T payload, {required String id}) {
    if (_closed) throw StateError('Realtime outbound queue is closed.');
    if (_pending.containsKey(id)) {
      throw ArgumentError.value(id, 'id', 'Already queued.');
    }
    if (_pending.length >= capacity) {
      throw StateError('Realtime outbound queue capacity has been reached.');
    }
    final RealtimeOutboundMessage<T> message =
        RealtimeOutboundMessage<T>(id: id, payload: payload);
    _pending[id] = message;
    _controller.add(message);
    return message;
  }

  bool acknowledge(String id) => _pending.remove(id) != null;

  /// Re-emits a failed message until [maxAttempts] is reached.
  RealtimeOutboundMessage<T>? retry(String id) {
    final RealtimeOutboundMessage<T>? current = _pending[id];
    if (current == null || current.attempt + 1 >= maxAttempts) {
      _pending.remove(id);
      return null;
    }
    final RealtimeOutboundMessage<T> next = current.retry();
    _pending[id] = next;
    _controller.add(next);
    return next;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pending.clear();
    await _controller.close();
  }
}
