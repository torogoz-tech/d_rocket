/// The contract for a conflict resolution
/// strategy. The framework calls this when
/// applying a remote upsert to a row that already
/// exists locally (concurrent edit).
///
/// [localRow] is the current row in the local DB.
/// [remotePayload] is the row data the server is
/// pushing. Returns the merged row to apply.
typedef ConflictResolver = Map<String, Object?> Function(
  Map<String, Object?> localRow,
  Map<String, Object?> remotePayload,
);
