/// The persistence contract for sync state
/// (clientId + watermark).
///
/// The user implements this for their chosen
/// platform. Three reference implementations
/// ship with d_rocket:
///
/// * [InMemorySyncStateStore] — for tests.
/// * `FileSyncStateStore` — Dart VM / server.
/// * `SharedPreferencesSyncStateStore` — Flutter.
abstract class SyncStateStore {
  /// Returns the persisted clientId, or `null` if
  /// this is a first run.
  Future<String?> getClientIdAsync();

  /// Persists [clientId] for future reads.
  Future<void> setClientIdAsync(String clientId);

  /// Returns the persisted watermark, or `0` if
  /// none.
  Future<int> getWatermarkAsync();

  /// Persists [watermark] for future reads.
  Future<void> setWatermarkAsync(int watermark);

  /// Clears all state (for tests or for the user
  /// to reset their identity).
  Future<void> clearAsync();
}
