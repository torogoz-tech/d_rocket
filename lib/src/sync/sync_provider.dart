import 'sync_envelope.dart';

/// Contract for a sync backend.
///
/// Implementations:
/// * [InMemorySyncProvider] — for tests.
/// * [RestSyncProvider] — talks to a
/// remote REST endpoint.
///
/// Intentionally small (3 methods) so a REST /
/// Firebase / Supabase / custom backend can all
/// implement it.
abstract class SyncProvider {
  /// Receives the local [envelope] and returns
  /// the remote envelope (the changes that
  /// have happened on the server since
  /// `envelope.since`).
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope);

  /// Returns the current server-side watermark
  /// (e.g. the latest `version` of any change).
  /// The user can use this to bootstrap the
  /// local watermark.
  Future<int> currentWatermarkAsync();
}
