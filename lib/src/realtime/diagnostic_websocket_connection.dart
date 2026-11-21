import '../diagnostics/diagnostic_category.dart';
import '../diagnostics/diagnostic_event.dart';
import '../diagnostics/drocket_diagnostics.dart';
import 'websocket_connection.dart';
import 'websocket_message.dart';

/// WebSocket connection decorator that publishes DevTools events.
class DiagnosticWebSocketConnection implements WebSocketConnection {
  const DiagnosticWebSocketConnection(this.inner);

  final WebSocketConnection inner;

  /// Preserves an optional HTTP upgrade status from decorated transports.
  int? get statusCode {
    try {
      final dynamic value = inner;
      final Object? status = value.statusCode;
      return status is int ? status : null;
    } on NoSuchMethodError {
      return null;
    }
  }

  @override
  Stream<WebSocketMessage> get messages => inner.messages.map((message) {
        _record('message');
        return message;
      });

  @override
  bool get isConnected => inner.isConnected;

  @override
  Future<void> connect(Uri url, {Map<String, String>? headers}) async {
    try {
      await inner.connect(url, headers: headers);
      _record('connect');
    } catch (error) {
      _record('connect', error: error);
      rethrow;
    }
  }

  @override
  Future<void> send(WebSocketMessage message) async {
    await inner.send(message);
    _record('send');
  }

  @override
  Future<void> close({int? code, String? reason}) async {
    await inner.close(code: code, reason: reason);
    _record('close');
  }

  void _record(String operation, {Object? error}) {
    DrocketDiagnostics.instance.record(
      DiagnosticEvent(
        category: DiagnosticCategory.realtime,
        operation: operation,
        startedAt: DateTime.now(),
        success: error == null,
        error: error?.toString(),
      ),
    );
  }
}
