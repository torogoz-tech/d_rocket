import 'dart:async';

import 'sync_trigger.dart';

/// Periodic timer trigger. The user provides an
/// [interval] and a [jitter] (default 10% of the
/// interval). The trigger fires every
/// `interval + jitter` (jitter avoids synchronised
/// spikes when many devices wake up at the same
/// time).
class PeriodicSyncTrigger implements SyncTrigger {
  PeriodicSyncTrigger({
    required this.interval,
    this.jitter = Duration.zero,
  });

  /// Base interval between syncs.
  final Duration interval;

  /// Random jitter (default 0 — no jitter).
  final Duration jitter;

  Timer? _timer;

  @override
  void start(Future<void> Function() onTrigger) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (Timer _) async {
      await onTrigger();
    });
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
