/// `ChangeTracker` — + (reactive queries).
///
/// Tracks every entity that the user has staged in a
/// [DbContext] (via `DbSet.add`, `DbSet.markModified`,
/// `DbSet.markDeleted`). The tracker is the single source
/// of truth for the in-memory state of the context.
///
///: the tracker is now a `ChangeNotifier` —
/// any subscriber of [changes] receives a
/// [ChangeEvent] for every state transition. This powers
/// [DbSet.asQueryable] / [Queryable.watch] for
/// reactive queries that re-execute when the underlying
/// rows change.
///
/// Thread-safety: not thread-safe. The user is expected to
/// confine the context (and its tracker) to a single isolate.
library;

import 'dart:async';

import 'tracked_entry.dart';

export 'tracked_entry.dart';

/// A single change event emitted by [ChangeTracker].
///
/// `type` is the kind of transition that triggered the
/// event. `entity` is the affected entity (or `null`
/// for batch events). The current [TrackedEntry] is
/// available via [ChangeTracker.entries] (the user can
/// look it up by PK).
class ChangeEvent {
  /// Creates a [ChangeEvent].
  const ChangeEvent({required this.type, this.entity, this.trackedEntry});

  /// The kind of transition: an entity was added to
  /// the tracker, modified, removed, or the entire
  /// tracker was cleared (e.g. on `untrackAll`).
  final ChangeEventType type;

  /// The affected entity, or `null` for batch events
  /// (e.g. `Cleared`).
  final Object? entity;

  /// The current [TrackedEntry] for [entity], or
  /// `null` for batch events.
  final TrackedEntry? trackedEntry;
}

/// The kind of a [ChangeEvent].
enum ChangeEventType {
  /// An entity was added to the tracker (e.g. via
  /// `DbSet.add`).
  added,

  /// An entity's state was changed to `modified`
  /// (e.g. via `DbSet.markModified`).
  modified,

  /// An entity was marked for deletion (e.g. via
  /// `DbSet.markDeleted`).
  removed,

  /// An entity's state was reset to `unchanged`
  /// (e.g. after a successful `saveChanges`).
  saved,

  /// The entire tracker was cleared (e.g. via
  /// `clear`).
  cleared,
}

class ChangeTracker {
  /// All currently-tracked entities, keyed by their PK (boxed
  /// as a `String` for `Map` compatibility — ints and Strings
  /// stringify cleanly, and a custom PK type would just be
  /// `.toString`'d). For `Added` entities with no PK yet, the
  /// key is the literal `'<pending:<id>>'` placeholder; the
  /// `SaveChanges` flow re-keys the entry after the insert.
  final Map<String, TrackedEntry> _entries = <String, TrackedEntry>{};

  ///: broadcast stream of [ChangeEvent]s.
  /// Subscribers of [changes] receive an event for every
  /// state transition.
  final StreamController<ChangeEvent> _changes =
      StreamController<ChangeEvent>.broadcast();

  /// Total number of tracked entries (across all states).
  int get length => _entries.length;

  /// Snapshot of every tracked entry, in insertion order. The
  /// returned list is a copy.
  List<TrackedEntry> get entries => _entries.values.toList(growable: false);

  ///: broadcast stream of [ChangeEvent]s. The
  /// stream is fed by [track], [untrack], [rekey], and
  /// [clear]. Subscribers (e.g. `dbSet.linq.watch`)
  /// re-execute their queries on every event.
  Stream<ChangeEvent> get changes => _changes.stream;

  /// Closes the underlying [StreamController]. Call this
  /// from `DbContext.dispose` to release the
  /// stream's resources. After [dispose], [changes] is
  /// closed and no more events are emitted.
  Future<void> dispose() async {
    if (!_changes.isClosed) await _changes.close();
  }

  /// Returns the tracked entry for [pk], or `null` if not
  /// tracked. The lookup uses the [String] rendering of [pk]
  /// (see the [_entries] field for the rationale).
  TrackedEntry? operator [](Object? pk) {
    if (pk == null) return null;
    return _entries[pk.toString()];
  }

  /// Tracks [entity] in state [state], recording [originalValues]
  /// as the pre-modification snapshot (only meaningful for
  /// `Modified`; the tracker does not interpret the values).
  ///
  /// If the entity is already tracked, the existing entry's
  /// state is updated to [state] and the original values are
  /// reset to the supplied [originalValues] (an empty map is
  /// fine for `Added` / `Unchanged` / `Removed`).
  void track(
    Object entity,
    EntityState state, {
    Map<String, Object?>? originalValues,
  }) {
    final TrackedEntry entry = TrackedEntry(
      entity: entity,
      state: state,
      originalValues: originalValues,
    );
    _entries[_keyOf(entity, originalValues: originalValues)] = entry;
    _emit(ChangeEvent(
      type: state == EntityState.added
          ? ChangeEventType.added
          : state == EntityState.modified
              ? ChangeEventType.modified
              : state == EntityState.removed
                  ? ChangeEventType.removed
                  : ChangeEventType.saved,
      entity: entity,
      trackedEntry: entry,
    ));
  }

  /// Removes the tracked entry whose PK is [pk] (returns
  /// `true` if something was removed, `false` otherwise).
  bool untrack(Object? pk) {
    if (pk == null) return false;
    final TrackedEntry? removed = _entries.remove(pk.toString());
    if (removed != null) {
      _emit(ChangeEvent(
        type: ChangeEventType.removed,
        entity: removed.entity,
        trackedEntry: removed,
      ));
    }
    return removed != null;
  }

  /// Drops every tracked entry. After this call, the tracker
  /// is empty. The user rarely needs this; tests use it for
  /// isolation between cases.
  void clear() {
    _entries.clear();
    _emit(const ChangeEvent(type: ChangeEventType.cleared));
  }

  /// Re-keys the entry for [oldPk] to [newPk] in-place. Used
  /// by `SaveChanges` after a `Added` row has been inserted
  /// and the DB-assigned PK is known.
  void rekey(Object? oldPk, Object newPk) {
    if (oldPk == null) return;
    final String oldKey = oldPk.toString();
    final TrackedEntry? e = _entries.remove(oldKey);
    if (e != null) {
      _entries[newPk.toString()] = e;
    }
  }

  ///: emits a [ChangeEvent] for a successful
  /// `saveChanges`. The user-facing `DbSet.saveChanges`
  /// / `DbContext.saveChanges` calls this once per
  /// batch so `watch` subscribers know the in-memory
  /// state has settled.
  void emitSaved() {
    _emit(const ChangeEvent(type: ChangeEventType.saved));
  }

  void _emit(ChangeEvent event) {
    if (_changes.isClosed) return;
    _changes.add(event);
  }

  /// Computes the key for [entity]. We don't have a type-safe
  /// PK accessor in the MVP, so we use a placeholder based on
  /// `identityHashCode` (object identity). `SaveChanges`
  /// re-keys the entry to its real PK after the insert.
  static String _keyOf(
    Object entity, {
    Map<String, Object?>? originalValues,
  }) {
    if (originalValues != null && originalValues.isNotEmpty) {
      // The caller has supplied real column values; use the
      // PK field as the key. We don't yet know which column
      // is the PK at runtime (the meta is a separate object),
      // so the DbSet is responsible for calling
      // `rekey` with the real PK after `track`.
    }
    return '<pending:${identityHashCode(entity)}>';
  }
}
