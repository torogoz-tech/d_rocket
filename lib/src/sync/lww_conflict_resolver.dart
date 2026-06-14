import 'conflict_resolver.dart';

/// The default strategy — Last Write Wins. The
/// remote row is applied verbatim (no merging).
class LwwConflictResolver {
  /// Returns a [ConflictResolver] that always
  /// picks the remote row.
  static ConflictResolver get instance =>
      (Map<String, Object?> localRow, Map<String, Object?> remotePayload) =>
          <String, Object?>{...localRow, ...remotePayload};
}
