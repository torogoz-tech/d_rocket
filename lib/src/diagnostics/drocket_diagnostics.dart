import 'dart:async';
import 'dart:developer' as developer;

import 'diagnostic_event.dart';

/// Development diagnostics hub shared by all d_rocket layers.
class DrocketDiagnostics {
  DrocketDiagnostics._();

  static final DrocketDiagnostics instance = DrocketDiagnostics._();

  final StreamController<DiagnosticEvent> _controller =
      StreamController<DiagnosticEvent>.broadcast();
  final List<DiagnosticEvent> _events = <DiagnosticEvent>[];

  bool enabled = false;
  bool publishToVmService = true;
  bool includeSensitiveData = false;
  int maxEvents = 500;

  Stream<DiagnosticEvent> get events => _controller.stream;
  List<DiagnosticEvent> get snapshot =>
      List<DiagnosticEvent>.unmodifiable(_events);

  void configure({
    bool? enabled,
    bool? publishToVmService,
    bool? includeSensitiveData,
    int? maxEvents,
  }) {
    if (enabled != null) this.enabled = enabled;
    if (publishToVmService != null) {
      this.publishToVmService = publishToVmService;
    }
    if (includeSensitiveData != null) {
      this.includeSensitiveData = includeSensitiveData;
    }
    if (maxEvents != null) {
      if (maxEvents < 1) {
        throw ArgumentError.value(maxEvents, 'maxEvents', 'must be positive');
      }
      this.maxEvents = maxEvents;
      _trim();
    }
  }

  void record(DiagnosticEvent event) {
    if (!enabled) return;
    _events.add(event);
    _trim();
    _controller.add(event);
    if (publishToVmService) {
      developer.postEvent('d_rocket.diagnostic', event.toJson());
    }
  }

  void clear() => _events.clear();

  void dispose() {
    _controller.close();
  }

  void _trim() {
    final int overflow = _events.length - maxEvents;
    if (overflow > 0) _events.removeRange(0, overflow);
  }
}
