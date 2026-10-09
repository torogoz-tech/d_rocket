import '../diagnostics/diagnostic_category.dart';
import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/drocket_diagnostics.dart';
import 'sse_connection.dart';
import 'sse_event.dart';

/// SSE connection decorator that publishes DevTools events.
class DiagnosticSseConnection implements SseConnection {
  const DiagnosticSseConnection(this.inner);

  final SseConnection inner;

  @override
  Stream<SseEvent> connect(
    Uri url, {
    Map<String, String>? headers,
    String? lastEventId,
  }) {
    _record('connect');
    return inner
        .connect(url, headers: headers, lastEventId: lastEventId)
        .map((event) {
      _record('message');
      return event;
    });
  }

  @override
  Future<void> close() async {
    await inner.close();
    _record('close');
  }

  void _record(String operation) {
    DrocketDiagnostics.instance.record(
      DiagnosticEvent(
        category: DiagnosticCategory.realtime,
        operation: operation,
        startedAt: DateTime.now(),
        success: true,
      ),
    );
  }
}
