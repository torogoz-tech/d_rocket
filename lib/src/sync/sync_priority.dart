/// 2.0.0 — sync priority / ordering.
///
/// A [SyncPriority] is a number that controls
/// the order in which [SyncTrigger]s fire when
/// multiple triggers are scheduled to fire at
/// the same time (or in the same event-loop
/// tick). Higher numbers fire first.
///
/// Default: `SyncPriority.normal` (0).
library;

/// A sync priority. Higher = fires first.
class SyncPriority {
  /// Critical: fires before everything else.
  /// Use for auth token refresh, security
  /// alerts, etc.
  static const SyncPriority critical = SyncPriority(1000);

  /// High: fires before normal triggers.
  /// Use for "user is looking at this screen
  /// right now" priorities.
  static const SyncPriority high = SyncPriority(100);

  /// Normal: the default. Most sync triggers.
  static const SyncPriority normal = SyncPriority(0);

  /// Low: fires after normal triggers.
  /// Use for background reconciliation.
  static const SyncPriority low = SyncPriority(-100);

  /// Background: fires last, when nothing
  /// else is going on. Use for "nice to have"
  /// syncs (e.g. analytics).
  static const SyncPriority background = SyncPriority(-1000);

  /// Creates a [SyncPriority] with a custom
  /// numeric value.
  const SyncPriority(this.value);

  /// The numeric value.
  final int value;

  /// Returns `true` if this priority fires
  /// before [other].
  bool firesBefore(SyncPriority other) => value > other.value;

  @override
  String toString() {
    if (this == critical) return 'critical';
    if (this == high) return 'high';
    if (this == normal) return 'normal';
    if (this == low) return 'low';
    if (this == background) return 'background';
    return 'custom($value)';
  }
}
