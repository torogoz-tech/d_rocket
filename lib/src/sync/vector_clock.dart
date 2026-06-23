/// 2.0.0 — vector clock for clock-skew
/// handling.
///
/// A [VectorClock] is a per-client counter
/// that increments on every change. The
/// server tracks the latest counter per
/// client. This is the standard solution to
/// the clock-skew problem in distributed
/// systems (no client clock is needed — only
/// the server's monotonic counter).
///
/// The vector clock is a `Map<String, int>`
/// of `clientId -> counter`. When two changes
/// conflict, the one with the higher counter
/// (per the client that made the change) wins.
library;

/// A vector clock — a map of
/// `clientId -> monotonic counter`.
class VectorClock {
  /// Creates a [VectorClock] from a map.
  VectorClock(this._counters);

  /// Creates an empty [VectorClock].
  VectorClock.empty() : _counters = <String, int>{};

  final Map<String, int> _counters;

  /// The current counters (read-only).
  Map<String, int> get counters => Map<String, int>.unmodifiable(_counters);

  /// The counter for [clientId], or 0 if no
  /// counter for that client.
  int counterFor(String clientId) => _counters[clientId] ?? 0;

  /// Increments the counter for [clientId]
  /// and returns the new value.
  int increment(String clientId) {
    final int next = (_counters[clientId] ?? 0) + 1;
    _counters[clientId] = next;
    return next;
  }

  /// Merges another vector clock into this
  /// one (takes the max of each counter).
  void merge(VectorClock other) {
    other._counters.forEach((String k, int v) {
      if (v > (_counters[k] ?? 0)) _counters[k] = v;
    });
  }

  /// `true` if this clock is **after**
  /// [other] in the happens-before order
  /// (i.e. at least one counter is higher
  /// and none are lower).
  bool isAfter(VectorClock other) {
    bool anyHigher = false;
    for (final String k in other._counters.keys) {
      final int mine = _counters[k] ?? 0;
      final int theirs = other._counters[k] ?? 0;
      if (mine < theirs) return false;
      if (mine > theirs) anyHigher = true;
    }
    for (final String k in _counters.keys) {
      if (!other._counters.containsKey(k)) anyHigher = true;
    }
    return anyHigher;
  }

  /// `true` if this clock and [other] are
  /// concurrent (neither is after the other).
  bool isConcurrentWith(VectorClock other) =>
      !isAfter(other) && !other.isAfter(this);

  @override
  String toString() => 'VectorClock($_counters)';
}
