/// 2.0.0 — sync progress reporting.
///
/// Emitted by `DbContext.syncAsync` (and the
/// trigger-driven version) to give the caller a
/// real-time view of where the sync round-trip
/// is. Used by the UI to render a "Syncing
/// 247/1000..." spinner, by tests to assert on
/// phase ordering, and by telemetry hooks to
/// record sync durations.
///
/// ## Design
///
/// `SyncProgress` is a value type (immutable,
/// `==`/`hashCode` by value). The
/// [SyncProgressEventBus] is a per-context
/// broadcast stream of these values — one
/// subscription, one event per phase transition
/// (not per row), and the latest event is
/// always re-emitted to new subscribers (so a
/// late UI can show "currently applying" the
/// moment it starts listening).
///
/// The phase enum is [SyncPhase].
///
/// ## Example
///
/// ```dart
/// // Stream variant:
/// final sub = ctx.syncProgress.listen((p) {
///   print('${p.phase}: ${p.processed}/${p.total}');
/// });
///
/// // Callback variant:
/// await ctx.syncAsync(
///   provider,
///   onProgress: (p) {
///     if (p.phase == SyncPhase.applying) {
///       spinner.value = p.processed / (p.total ?? 1);
///     }
///   },
/// );
/// ```
library;

import 'dart:async';

/// The high-level phase of a sync round-trip.
///
/// The transitions are:
/// ```
/// starting
///   → pushing
///       → retrying (back to pushing)
///       → pulling
///           → applying
///               → retrying (back to applying)
///               → done | error
/// ```
///
/// `done` and `error` are terminal — the next
/// `syncAsync` call starts a new round-trip from
/// `starting`.
enum SyncPhase {
  /// The queue is being read (either from the
  /// in-memory cache or the persistent
  /// [SyncQueueStore]). One event, then
  /// transition to `pushing`.
  starting,

  /// Local changes are being sent to the
  /// [SyncProvider]. `processed` is the number
  /// of local changes pushed so far; `total`
  /// is the total number to push.
  pushing,

  /// The remote envelope is being received.
  /// `processed` is the number of remote
  /// changes received so far; `total` is
  /// usually `null` (we don't know the count
  /// until the response is fully received).
  pulling,

  /// Remote changes are being applied to the
  /// local DB. `processed` is the number
  /// applied so far; `total` is the number
  /// to apply (the size of the remote
  /// envelope).
  applying,

  /// Between retry attempts. `processed` is
  /// the attempt count, `total` is the
  /// max-attempts from the [RetryPolicy].
  /// The next event is back to `pushing` or
  /// `applying`.
  retrying,

  /// Terminal: the sync succeeded. `processed`
  /// == `total` (always).
  done,

  /// Terminal: the sync failed. The [error]
  /// and [stackTrace] fields of
  /// [SyncProgress] are set.
  error,
}

/// A single value emitted by
/// `DbContext.syncAsync` (or the trigger-driven
/// version) during a sync round-trip.
///
/// Immutable, value-typed. The `==` operator
/// compares all fields so subscribers can
/// de-duplicate or assert on equality.
class SyncProgress {
  /// Creates a [SyncProgress]. The [timestamp]
  /// defaults to `DateTime.now()`.
  SyncProgress({
    required this.phase,
    this.processed = 0,
    this.total,
    this.message,
    this.error,
    this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// The current phase (see [SyncPhase]).
  final SyncPhase phase;

  /// How many items have been processed in
  /// this phase. 0 for `starting` and `error`.
  final int processed;

  /// The total number of items expected. May
  /// be `null` if the count isn't known (e.g.
  /// for `pulling` — we don't know how many
  /// remote changes the server will return
  /// until the response is fully received).
  final int? total;

  /// A human-readable message. For
  /// `error`, this is `error.toString()`.
  /// For `retrying`, this is the delay until
  /// the next attempt (e.g. `"2.5s"`).
  final String? message;

  /// The error that caused the failure (only
  /// set when [phase] is [SyncPhase.error]).
  final Object? error;

  /// The stack trace of the error (only set
  /// when [phase] is [SyncPhase.error]).
  final StackTrace? stackTrace;

  /// When this event was created. Useful for
  /// latency analysis in tests.
  final DateTime timestamp;

  /// `0.0..1.0` progress fraction, or `null`
  /// if the total is unknown.
  double? get fraction {
    if (total == null || total == 0) return null;
    final double f = processed / total!;
    if (f.isNaN || f.isInfinite) return null;
    if (f < 0) return 0.0;
    if (f > 1) return 1.0;
    return f;
  }

  /// `true` when [phase] is [SyncPhase.done]
  /// or [SyncPhase.error].
  bool get isTerminal =>
      phase == SyncPhase.done || phase == SyncPhase.error;

  /// `true` when the [SyncProgress.error] is
  /// set.
  bool get hasError => error != null;

  @override
  String toString() {
    final StringBuffer b = StringBuffer('SyncProgress(')
      ..write(phase.name)
      ..write(', processed=$processed');
    if (total != null) b.write('/$total');
    if (message != null) b.write(', message=$message');
    if (error != null) b.write(', error=$error');
    b.write(')');
    return b.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SyncProgress) return false;
    return phase == other.phase &&
        processed == other.processed &&
        total == other.total &&
        message == other.message &&
        error == other.error &&
        timestamp == other.timestamp;
  }

  @override
  int get hashCode => Object.hash(
        phase,
        processed,
        total,
        message,
        error,
        timestamp,
      );
}

/// A per-context broadcast stream of
/// [SyncProgress] events. Owned by [DbContext]
/// (one instance per context). Subscribers
/// always see the **latest** event first
/// (replay-1), so a late UI can show
/// "currently applying" the moment it starts
/// listening.
class SyncProgressEventBus {
  final StreamController<SyncProgress> _controller =
      StreamController<SyncProgress>.broadcast(
    sync: true,
  );
  SyncProgress _latest = SyncProgress(phase: SyncPhase.done);

  /// The latest [SyncProgress] event. Updated
  /// synchronously by [emit] (before the
  /// stream listener fires).
  SyncProgress get latest => _latest;

  /// Subscribes to the stream of [SyncProgress]
  /// events. New subscribers always receive the
  /// [latest] event first (replay-1), then any
  /// future events.
  Stream<SyncProgress> get stream {
    // We use a transformer-style approach:
    // the returned stream is a single-subscription
    // stream that yields the latest first, then
    // listens to the broadcast controller.
    late StreamController<SyncProgress> wrapper;
    StreamSubscription<SyncProgress>? sub;
    StreamSubscription<SyncProgress>? replaySub;
    final Completer<void> replayDone = Completer<void>();
    wrapper = StreamController<SyncProgress>(
      onListen: () {
        // Replay the latest synchronously.
        wrapper.add(_latest);
        // Then subscribe to the broadcast.
        sub = _controller.stream.listen(wrapper.add,
            onError: wrapper.addError, onDone: wrapper.close);
        // Close the wrapper when the controller closes.
        replaySub = _controller.stream.listen(
          (_) {},
          onDone: () {
            if (!replayDone.isCompleted) replayDone.complete();
          },
        );
      },
      onCancel: () async {
        await sub?.cancel();
        await replaySub?.cancel();
      },
    );
    return wrapper.stream;
  }

  /// Emits a [SyncProgress] event. Updates
  /// [latest] synchronously (so a listener that
  /// subscribes immediately after the emit
  /// still sees the value).
  void emit(SyncProgress progress) {
    _latest = progress;
    if (!_controller.isClosed) {
      _controller.add(progress);
    }
  }

  /// Closes the stream. Called by
  /// `DbContext.dispose` (and by tests in
  /// `tearDown`).
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
