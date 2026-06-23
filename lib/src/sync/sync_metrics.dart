/// 2.0.0 — sync telemetry.
///
/// The [SyncMetrics] class records sync
/// statistics for telemetry. The caller can
/// subscribe to the [Stream] of
/// [SyncMetricsSnapshot]s and ship them to
/// their telemetry backend (Datadog, Sentry,
/// etc.).
///
/// ## Metrics tracked
///
/// * `roundTrips` — total syncAsync calls.
/// * `pushed` — total local changes pushed.
/// * `pulled` — total remote changes received.
/// * `applied` — total remote changes applied.
/// * `conflicts` — total conflicts encountered.
/// * `errors` — total sync errors.
/// * `avgDuration` — average sync duration.
/// * `p95Duration` — 95th percentile sync duration.
library;

import 'dart:async';

/// A snapshot of sync metrics at a point in
/// time.
class SyncMetricsSnapshot {
  /// Creates a [SyncMetricsSnapshot].
  const SyncMetricsSnapshot({
    required this.roundTrips,
    required this.changesPushed,
    required this.changesPulled,
    required this.changesApplied,
    required this.conflicts,
    required this.errors,
    required this.avgDurationMicros,
    required this.p95DurationMicros,
    required this.timestamp,
  });

  /// Total sync round-trips.
  final int roundTrips;

  /// Total local changes pushed.
  final int changesPushed;

  /// Total remote changes pulled.
  final int changesPulled;

  /// Total remote changes applied.
  final int changesApplied;

  /// Total conflicts encountered.
  final int conflicts;

  /// Total errors.
  final int errors;

  /// Average sync duration (microseconds).
  final double avgDurationMicros;

  /// p95 sync duration (microseconds).
  final double p95DurationMicros;

  /// When this snapshot was created.
  final DateTime timestamp;
}

/// A simple sync metrics recorder.
class SyncMetrics {
  int _roundTrips = 0;
  int _changesPushed = 0;
  int _changesPulled = 0;
  int _changesApplied = 0;
  int _conflicts = 0;
  int _errors = 0;
  final List<int> _durations = <int>[];

  final StreamController<SyncMetricsSnapshot> _controller =
      StreamController<SyncMetricsSnapshot>.broadcast(sync: true);

  /// A broadcast stream of [SyncMetricsSnapshot]s.
  /// New subscribers receive the latest snapshot
  /// (replay-1).
  Stream<SyncMetricsSnapshot> get stream {
    late StreamController<SyncMetricsSnapshot> wrapper;
    StreamSubscription<SyncMetricsSnapshot>? sub;
    wrapper = StreamController<SyncMetricsSnapshot>(
      onListen: () {
        wrapper.add(snapshot);
        sub = _controller.stream.listen(wrapper.add);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return wrapper.stream;
  }

  /// Records a completed sync round-trip.
  void recordRoundTrip({
    required int pushed,
    required int pulled,
    required int applied,
    required int conflicts,
    required int durationMicros,
  }) {
    _roundTrips++;
    _changesPushed += pushed;
    _changesPulled += pulled;
    _changesApplied += applied;
    _conflicts += conflicts;
    _durations.add(durationMicros);
    _controller.add(snapshot);
  }

  /// Records a sync error (without changing
  /// the round-trip count).
  void recordError() {
    _errors++;
    _controller.add(snapshot);
  }

  /// A current snapshot of the metrics.
  SyncMetricsSnapshot get snapshot {
    final double avg = _durations.isEmpty
        ? 0.0
        : _durations.reduce((int a, int b) => a + b) / _durations.length;
    final double p95 = _durations.isEmpty
        ? 0.0
        : (_durations.toList()..sort())[(_durations.length * 0.95)
            .floor()
            .clamp(0, _durations.length - 1)]
            .toDouble();
    return SyncMetricsSnapshot(
      roundTrips: _roundTrips,
      changesPushed: _changesPushed,
      changesPulled: _changesPulled,
      changesApplied: _changesApplied,
      conflicts: _conflicts,
      errors: _errors,
      avgDurationMicros: avg,
      p95DurationMicros: p95,
      timestamp: DateTime.now(),
    );
  }

  /// Closes the underlying stream. Tests
  /// should call this in `tearDown`.
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
