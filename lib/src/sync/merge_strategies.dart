import 'conflict_resolver.dart';

/// Pre-built merge strategies for common cases.
class MergeStrategies {
  /// Take the local value for [localColumns]
  /// and the remote value for everything else.
  ///
  /// Example: for a `users` table where the
  /// user edits their own `display_name` on
  /// device A while an admin edits `role` on
  /// device B, the merge is: keep A's
  /// `display_name`, take B's `role`.
  static ConflictResolver preferLocalColumns(List<String> localColumns) {
    return (Map<String, Object?> localRow, Map<String, Object?> remotePayload) {
      final Map<String, Object?> merged = <String, Object?>{
        ...remotePayload,
      };
      for (final String col in localColumns) {
        if (localRow.containsKey(col)) {
          merged[col] = localRow[col];
        }
      }
      return merged;
    };
  }

  /// Take the remote value for [remoteColumns]
  /// and the local value for everything else.
  static ConflictResolver preferRemoteColumns(List<String> remoteColumns) {
    return (Map<String, Object?> localRow, Map<String, Object?> remotePayload) {
      final Map<String, Object?> merged = <String, Object?>{
        ...localRow,
      };
      for (final String col in remoteColumns) {
        if (remotePayload.containsKey(col)) {
          merged[col] = remotePayload[col];
        }
      }
      return merged;
    };
  }

  /// Take the max of two numeric columns.
  /// Useful for monotonically increasing counters.
  static ConflictResolver maxOf(List<String> counterColumns) {
    return (Map<String, Object?> localRow, Map<String, Object?> remotePayload) {
      final Map<String, Object?> merged = <String, Object?>{
        ...localRow,
      };
      for (final String col in counterColumns) {
        final Object? localVal = localRow[col];
        final Object? remoteVal = remotePayload[col];
        if (localVal is num && remoteVal is num) {
          merged[col] = localVal > remoteVal ? localVal : remoteVal;
        } else if (remoteVal != null) {
          merged[col] = remoteVal;
        }
      }
      // Default LWW for the rest.
      for (final MapEntry<String, Object?> entry in remotePayload.entries) {
        if (!counterColumns.contains(entry.key)) {
          merged[entry.key] = entry.value;
        }
      }
      return merged;
    };
  }
}
