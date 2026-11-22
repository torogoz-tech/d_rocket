import 'sync_change.dart';
import 'sync_change_type.dart';

/// Computes field-level synchronization changes between two snapshots.
class DeltaSync {
  DeltaSync._();

  /// Returns an empty list when two snapshots are equal.
  static List<SyncChange> diff({
    required String tableName,
    required String primaryKey,
    required Map<String, Object?> previous,
    required Map<String, Object?>? current,
    required int version,
    String? changeId,
  }) {
    final String pk = '${previous[primaryKey] ?? current?[primaryKey]}';
    if (current == null) {
      return <SyncChange>[
        SyncChange(
          tableName: tableName,
          pk: pk,
          type: SyncChangeType.delete,
          payload: null,
          version: version,
          changeId: changeId,
        ),
      ];
    }
    final Map<String, Object?> changed = <String, Object?>{};
    for (final MapEntry<String, Object?> entry in current.entries) {
      if (!previous.containsKey(entry.key) || previous[entry.key] != entry.value) {
        changed[entry.key] = entry.value;
      }
    }
    if (changed.isEmpty) return const <SyncChange>[];
    return <SyncChange>[
      SyncChange(
        tableName: tableName,
        pk: pk,
        type: SyncChangeType.upsert,
        payload: changed,
        version: version,
        changeId: changeId,
      ),
    ];
  }
}
