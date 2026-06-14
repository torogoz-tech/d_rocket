import 'dart:async';

/// Base interface for a sync trigger. The user
/// composes one or more triggers and hands them
/// to [DbContext.startSyncTriggers].
abstract class SyncTrigger {
  /// Starts the trigger. Calls [onTrigger]
  /// whenever the trigger fires. The user is
  /// expected to chain onTrigger to
  /// `ctx.syncAsync(...)`.
  void start(Future<void> Function() onTrigger);

  /// Stops the trigger. Called from
  /// [DbContext.stopSyncTriggers] (or
  /// automatically on context dispose).
  void stop();
}
