/// The kind of change encoded in a [SyncChange].
enum SyncChangeType {
  /// Insert or update a row.
  upsert,

  /// Delete a row.
  delete,
}
