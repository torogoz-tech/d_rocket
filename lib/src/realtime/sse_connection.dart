import 'sse_event.dart';

/// Abstract contract for an SSE connection.
///
/// Implementations:
/// * [HttpSseClient] — `package:http` (Dart VM +
/// Flutter + web).
abstract class SseConnection {
  /// Completes when the connection attempt has received its initial response.
  /// Existing implementations can keep the default immediate completion.
  Future<void> get ready => Future<void>.value();

  /// HTTP status returned by the most recent connection attempt, when known.
  int? get statusCode => null;

  /// Activity emitted by the transport, including protocol heartbeats.
  Stream<void> get activity => const Stream<void>.empty();

  /// Opens a connection to [url] and returns a
  /// stream of [SseEvent]s. The stream ends when
  /// the server closes the connection. The
  /// [lastEventId] is sent as the `Last-Event-ID`
  /// header (so the server can resume from where
  /// we left off).
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  });

  /// Closes the active connection (if any). The
  /// next [connect] call will open a fresh one.
  Future<void> close();
}
