import 'dart:async';

/// Routes realtime payloads to independent named channels.
class RealtimeMultiplexer<T> {
  final Map<String, StreamController<T>> _channels =
      <String, StreamController<T>>{};
  bool _closed = false;

  /// Returns a broadcast stream for [name], creating it on first use.
  Stream<T> channel(String name) {
    _ensureOpen();
    return (_channels[name] ??= StreamController<T>.broadcast()).stream;
  }

  /// Publishes [payload] only to subscribers of [name].
  void publish(String name, T payload) {
    _ensureOpen();
    final StreamController<T>? controller = _channels[name];
    if (controller != null && !controller.isClosed) controller.add(payload);
  }

  /// Closes every channel and prevents new channels from being created.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final StreamController<T> controller in _channels.values) {
      await controller.close();
    }
    _channels.clear();
  }

  void _ensureOpen() {
    if (_closed) throw StateError('Realtime multiplexer is closed.');
  }
}
