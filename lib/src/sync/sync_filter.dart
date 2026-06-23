/// 2.0.0 — selective sync.
///
/// The [SyncFilter] tells the sync layer **which
/// tables** and **which rows** to include in a
/// round-trip. Without a filter, every
/// `syncAsync` call ships and applies every
/// change — fine for small apps, expensive for
/// apps with millions of rows or hundreds of
/// tables.
///
/// ## Use cases
///
/// * **Per-user sync**: "sync only rows where
///   `userId = me`". Save bandwidth + memory.
/// * **Per-table sync**: "sync only the
///   `orders` table right now, not `customers`".
///   (This is the per-trigger variant — see
///   [ScopedSyncFilter].)
/// * **Time-windowed sync**: "sync only rows
///   from the last 30 days".
/// * **Privacy filters**: "never sync rows
///   marked `isDeleted = true`".
///
/// ## Example
///
/// ```dart
/// // Per-user filter.
/// final filter = ExpressionSyncFilter<User>(
///   tableName: 'users',
///   predicate: (u) => u.userId == me.id,
/// );
///
/// // Apply on sync.
/// await ctx.syncAsync(
///   provider,
///   filters: [filter],
/// );
/// ```
library;

import 'sync_change.dart';

/// A filter that decides which [SyncChange]s
/// are pushed and which remote changes are
/// applied during a sync round-trip.
///
/// Implementations:
///
/// * [AllowAllSyncFilter] — no filter, the
///   default. Every change is included.
/// * [TableNameSyncFilter] — include only
///   changes for the given table(s).
/// * [ExpressionSyncFilter<T>] — include only
///   changes whose rows match a predicate
///   (record-level filter).
/// * [ScopedSyncFilter] — compose multiple
///   filters (AND / OR).
///
/// ## Design
///
/// A [SyncFilter] is a **value object** that the
/// sync layer reads during a round-trip. It does
/// NOT hold state. To make a filter dynamic
/// (e.g. "the current user's id"), wrap it in a
/// closure or use a function-based filter
/// ([FilterBuilder]).
abstract interface class SyncFilter {
  /// `true` if [change] should be included in
  /// the round-trip. The sync layer calls this
  /// once per [SyncChange] during the pushing
  /// phase (for local changes) and once during
  /// the applying phase (for remote changes).
  bool matches(SyncChange change);

  /// The human-readable name of this filter.
  /// Used in error messages and logs.
  String get name;
}

/// A no-op filter that includes every change.
/// The default for `DbContext.syncAsync` when
/// no `filters` are passed.
class AllowAllSyncFilter implements SyncFilter {
  /// Creates an [AllowAllSyncFilter].
  const AllowAllSyncFilter();

  @override
  bool matches(SyncChange change) => true;

  @override
  String get name => 'allow-all';
}

/// A filter that includes only changes for the
/// given table(s). Use this to scope a
/// round-trip to a single table or a set of
/// tables.
///
/// Example:
/// ```dart
/// // Sync only the `orders` table.
/// final filter = TableNameSyncFilter({'orders'});
/// await ctx.syncAsync(provider, filters: [filter]);
/// ```
class TableNameSyncFilter implements SyncFilter {
  /// Creates a [TableNameSyncFilter] that
  /// includes changes for any of [tables].
  const TableNameSyncFilter(this.tables);

  /// The set of table names to include.
  final Set<String> tables;

  @override
  bool matches(SyncChange change) => tables.contains(change.tableName);

  @override
  String get name => 'table-name:$tables';
}

/// A filter that includes only changes whose
/// row matches a predicate. The predicate is a
/// `(Map<String, Object?> row) -> bool` — the
/// row is the column-value map for the change.
///
/// Example (per-user):
/// ```dart
/// final filter = RecordSyncFilter(
///   tableName: 'orders',
///   predicate: (row) => row['userId'] == me.id,
/// );
/// ```
class RecordSyncFilter implements SyncFilter {
  /// Creates a [RecordSyncFilter] for
  /// [tableName]. The [predicate] is applied to
  /// the row's column-value map.
  RecordSyncFilter({
    required this.tableName,
    required this.predicate,
  });

  /// The table this filter applies to.
  final String tableName;

  /// The predicate. `true` to include the
  /// change, `false` to skip it.
  final bool Function(Map<String, Object?> row) predicate;

  @override
  bool matches(SyncChange change) {
    if (change.tableName != tableName) return false;
    final Map<String, Object?>? payload = change.payload;
    if (payload == null) return false; // delete or no payload
    return predicate(payload);
  }

  @override
  String get name => 'record:$tableName';
}

/// A composite filter that ANDs or ORs the
/// results of [filters].
///
/// Example:
/// ```dart
/// // Per-user AND per-table.
/// final filter = ScopedSyncFilter.and([
///   TableNameSyncFilter({'orders'}),
///   RecordSyncFilter(
///     tableName: 'orders',
///     predicate: (row) => row['userId'] == me.id,
///   ),
/// ]);
/// ```
class ScopedSyncFilter implements SyncFilter {
  /// Creates an AND composite.
  ScopedSyncFilter.and(List<SyncFilter> filters)
      : _filters = filters,
        _combinator = _andCombinator;

  /// Creates an OR composite.
  ScopedSyncFilter.or(List<SyncFilter> filters)
      : _filters = filters,
        _combinator = _orCombinator;

  final List<SyncFilter> _filters;
  final bool Function(SyncChange, Iterable<bool>) _combinator;

  static bool _andCombinator(SyncChange _, Iterable<bool> results) =>
      results.every((b) => b);
  static bool _orCombinator(SyncChange _, Iterable<bool> results) =>
      results.any((b) => b);

  @override
  bool matches(SyncChange change) =>
      _combinator(change, _filters.map((f) => f.matches(change)));

  @override
  String get name => 'scoped(${_filters.length} filters)';
}
