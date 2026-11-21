import 'dart:async';
import 'dart:developer' as developer;

import 'diagnostic_event.dart';
import 'diagnostic_policy.dart';

/// Development diagnostics hub shared by all d_rocket layers.
class DrocketDiagnostics {
  DrocketDiagnostics._();

  static final DrocketDiagnostics instance = DrocketDiagnostics._();

  final StreamController<DiagnosticEvent> _controller =
      StreamController<DiagnosticEvent>.broadcast();
  final List<DiagnosticEvent> _events = <DiagnosticEvent>[];
  int _sequence = 0;

  bool enabled = false;
  bool publishToVmService = true;
  bool includeSensitiveData = false;
  int maxPayloadLength = 32768;
  int maxEvents = 500;
  DiagnosticPolicy diagnosticPolicy = const DiagnosticPolicy();

  Stream<DiagnosticEvent> get events => _controller.stream;
  List<DiagnosticEvent> get snapshot =>
      List<DiagnosticEvent>.unmodifiable(_events);

  /// Executes an async LINQ operation inside a diagnostic context so a
  /// storage provider can distinguish generated LINQ SQL from direct SQL.
  Future<T> runLinq<T>(Future<T> Function() operation) {
    return runZoned(
      operation,
      zoneValues: <Object, Object?>{_linqZoneKey: true},
    );
  }

  bool get isLinqContext => Zone.current[_linqZoneKey] == true;

  void configure({
    bool? enabled,
    bool? publishToVmService,
    bool? includeSensitiveData,
    int? maxPayloadLength,
    int? maxEvents,
    DiagnosticPolicy? diagnosticPolicy,
  }) {
    if (enabled != null) this.enabled = enabled;
    if (publishToVmService != null) {
      this.publishToVmService = publishToVmService;
    }
    if (includeSensitiveData != null) {
      this.includeSensitiveData = includeSensitiveData;
    }
    if (maxPayloadLength != null) {
      if (maxPayloadLength < 1) {
        throw ArgumentError.value(
          maxPayloadLength,
          'maxPayloadLength',
          'must be positive',
        );
      }
      this.maxPayloadLength = maxPayloadLength;
    }
    if (maxEvents != null) {
      if (maxEvents < 1) {
        throw ArgumentError.value(maxEvents, 'maxEvents', 'must be positive');
      }
      this.maxEvents = maxEvents;
      _trim();
    }
    if (diagnosticPolicy != null) {
      this.diagnosticPolicy = diagnosticPolicy;
    }
  }

  void record(DiagnosticEvent event) {
    if (!enabled) return;
    final now = DateTime.now();
    final normalized = event.copyWith(
      id: event.id ??
          '${event.startedAt.microsecondsSinceEpoch}-${_sequence++}',
      finishedAt: event.finishedAt ??
          (event.duration == null ? now : event.startedAt.add(event.duration!)),
    );
    _events.add(normalized);
    _trim();
    _controller.add(normalized);
    if (publishToVmService) {
      developer.postEvent('d_rocket.diagnostic', normalized.toJson());
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

  static const Symbol _linqZoneKey = #drocketLinqContext;
}
