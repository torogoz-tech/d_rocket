/// `TrackedEntry` + `EntityState` — .
///
/// A [TrackedEntry] is a single entity staged in the
/// [ChangeTracker] (one row per `DbSet.add` / `markModified`
/// / `markDeleted`). [EntityState] is the per-entry state
/// machine that drives the [DbContext.saveChanges]
/// dispatch order (inserts → updates → deletes).
library;

/// The state of a [TrackedEntry] in the change
/// tracker.
///
/// State transitions:
///
/// * `(none)` → `detached` (entity has no entry).
/// * `detached` → `added` on `DbSet.add`.
/// * `detached` → `modified` on `DbSet.markModified`.
/// * `detached` → `removed` on `DbSet.markDeleted`.
/// * `added` → `unchanged` on successful `saveChanges`.
/// * `modified` → `unchanged` on successful `saveChanges`.
/// * `removed` → `(untracked)` on successful `saveChanges`.
/// * `unchanged` → `modified` on `markModified`.
enum EntityState {
  /// The entity is not tracked (no entry in the
  /// [ChangeTracker]). The MVP `DbSet` does not expose
  /// `markDetached` directly — entries are created on
  /// `add` / `markModified` / `markDeleted` and removed
  /// on `saveChanges`. `detached` is the documented
  /// "no entry" sentinel used in API contracts.
  detached,

  /// The entity will be inserted by the next
  /// `saveChanges`. New entries start in this state.
  added,

  /// The entity is in sync with the database. Default
  /// state for entities loaded via `findById` / `toList`.
  unchanged,

  /// The entity will be updated by the next
  /// `saveChanges`. The original values are stored in
  /// [TrackedEntry.originalValues].
  modified,

  /// The entity will be deleted by the next
  /// `saveChanges`.
  removed,
}

/// A single entity tracked by the [ChangeTracker].
///
/// Created by `DbSet.add` / `markModified` / `markDeleted`,
/// consumed by `DbContext.saveChanges`. The
/// [originalValues] are the column values before the
/// user modified the entity (only meaningful when
/// [state] == [EntityState.modified]).
class TrackedEntry {
  /// Creates a tracked entry. The [entity] is the
  /// Dart-side instance, [state] is the current state,
  /// and [originalValues] is the pre-modification snapshot
  /// (only meaningful when [state] == [EntityState.modified]).
  TrackedEntry({
    required this.entity,
    required this.state,
    this.originalValues,
  });

  /// The user-facing entity instance.
  final Object entity;

  /// The current state of the entry.
  EntityState state;

  /// The pre-modification column values (only meaningful
  /// when [state] == [EntityState.modified]; `null` for
  /// other states).
  final Map<String, Object?>? originalValues;
}
