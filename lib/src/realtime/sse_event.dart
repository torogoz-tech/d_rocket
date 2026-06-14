/// A single Server-Sent Event.
///
/// Multiple `data:` lines in the wire format are
/// joined with `\n` and exposed as [data].
class SseEvent {
  const SseEvent({
    required this.data,
    this.event,
    this.id,
    this.retry,
  });

  /// Event payload (multiple `data:` lines joined
  /// with `\n`).
  final String data;

  /// Event name (default `"message"` if the server
  /// didn't specify one).
  final String? event;

  /// Event ID (sent via `id: <value>`).
  final String? id;

  /// Retry hint (sent via `retry: <ms>`).
  final Duration? retry;

  @override
  String toString() => 'SseEvent(event: $event, id: $id, '
      'data: ${data.length > 30 ? '${data.substring(0, 30)}...' : data})';
}
