import 'dart:async';

import 'sync_trigger.dart';

/// One-shot trigger that fires the next time the
/// user manually calls [fire]. Useful for
/// pull-to-refresh: the UI calls `fire` and the
/// sync runs.
class SignalSyncTrigger implements SyncTrigger {
  SignalSyncTrigger();

  final StreamController<void> _controller = StreamController<void>.broadcast();
  Future<void> Function()? _onTrigger;
  StreamSubscription<void>? _sub;

  @override
  void start(Future<void> Function() onTrigger) {
    _onTrigger = onTrigger;
    _sub = _controller.stream.listen((_) async {
      if (_onTrigger != null) {
        await _onTrigger!();
      }
    });
  }

  @override
  void stop() {
    _sub?.cancel();
    _sub = null;
    _onTrigger = null;
  }

  /// Fire the trigger (e.g. on pull-to-refresh).
  void fire() {
    _controller.add(null);
  }
}
