import 'signal_sync_trigger.dart';

/// Manual trigger that exposes [SignalSyncTrigger.fire]
/// so the user can integrate it with their own event
/// sources (e.g. a custom network-reconnect listener,
/// an app-lifecycle observer, etc.). Same as
/// [SignalSyncTrigger] but documented as "manual" to
/// make the intent clearer.
class ManualSyncTrigger extends SignalSyncTrigger {
  ManualSyncTrigger();
}
