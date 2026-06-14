import 'sync_change_type.dart';

/// One row in a [SyncEnvelope].
///
/// `tableName` is the local table name (matches
/// `EntityMeta.tableName`). `pk` is the primary
/// key value (serialised as a String for
/// transport). `payload` is the row data (a
/// `Map<String, Object?>` of column names to
/// values) — for `delete` changes, this is
/// `null`. `version` is a monotonically increasing
/// number (e.g. a millisecond timestamp) used for
/// last-write-wins conflict resolution.
class SyncChange {
  const SyncChange({
    required this.tableName,
    required this.pk,
    required this.type,
    required this.payload,
    required this.version,
  });

  /// The local table name.
  final String tableName;

  /// The primary key value (serialised as a
  /// String for transport).
  final String pk;

  /// The kind of change.
  final SyncChangeType type;

  /// The row data, or `null` for `delete`.
  final Map<String, Object?>? payload;

  /// Monotonically increasing version number
  /// (used for last-write-wins).
  final int version;

  /// JSON serialisation (for `RestSyncProvider`).
  /// The wire format is a flat map with one string
  /// for the type (so it's stable across renames).
  Map<String, Object?> toJson() => <String, Object?>{
        'tableName': tableName,
        'pk': pk,
        'type': type.name,
        'payload': payload,
        'version': version,
      };

  /// Inverse of [toJson].
  static SyncChange fromJson(Map<String, Object?> json) {
    return SyncChange(
      tableName: json['tableName']! as String,
      pk: json['pk']! as String,
      type: SyncChangeType.values
          .firstWhere((SyncChangeType t) => t.name == json['type']),
      payload: json['payload'] as Map<String, Object?>?,
      version: json['version']! as int,
    );
  }
}
