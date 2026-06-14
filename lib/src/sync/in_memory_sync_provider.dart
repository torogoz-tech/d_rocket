import 'sync_change.dart';
import 'sync_envelope.dart';
import 'sync_provider.dart';

/// In-memory [SyncProvider] that buffers changes
/// between "clients". Useful for tests and local
/// development without a network.
///
/// The same provider can simulate multiple
/// clients by holding a shared "history" list of
/// all changes and tracking per-client watermarks.
class InMemorySyncProvider implements SyncProvider {
  InMemorySyncProvider({
    String? clientId,
  }) : _clientId =
            clientId ?? 'memory-${DateTime.now().microsecondsSinceEpoch}';

  // ignore: unused_field
  final String _clientId;

  /// Shared history of all changes (across all
  /// clients). Append-only during a sync.
  final List<SyncChange> _history = <SyncChange>[];

  /// Per-client watermarks (the last version
  /// each client has seen).
  final Map<String, int> _clientWatermarks = <String, int>{};

  /// Server-side watermark — increments on every
  /// push.
  int _watermark = 0;

  /// Log of every push (so tests can assert what
  /// was sent).
  final List<SyncEnvelope> pushLog = <SyncEnvelope>[];

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    pushLog.add(envelope);
    // Re-stamp each change's version with the
    // SERVER-side watermark (so all clients see
    // a consistent ordering, regardless of what
    // the client sent).
    for (final SyncChange c in envelope.changes) {
      _watermark++;
      _history.add(SyncChange(
        tableName: c.tableName,
        pk: c.pk,
        type: c.type,
        payload: c.payload,
        version: _watermark,
      ));
    }
    // Return the changes for THIS client since
    // the watermark they last saw, MINUS the
    // changes the client itself just pushed
    // (so it doesn't re-apply its own work).
    final int clientSince = _clientWatermarks[envelope.clientId] ?? 0;
    final List<SyncChange> pending =
        _history.where((SyncChange c) => c.version > clientSince).toList();
    final List<SyncChange> filtered = <SyncChange>[];
    final Set<String> ownKeys = <String>{
      for (final SyncChange c in envelope.changes) '${c.tableName}/${c.pk}',
    };
    for (final SyncChange c in pending) {
      if (ownKeys.contains('${c.tableName}/${c.pk}')) continue;
      filtered.add(c);
    }
    _clientWatermarks[envelope.clientId] = _watermark;
    return SyncEnvelope(
      clientId: envelope.clientId,
      since: _watermark,
      changes: filtered,
    );
  }

  @override
  Future<int> currentWatermarkAsync() async => _watermark;

  /// Clear all state (for `setUp`).
  void reset() {
    _history.clear();
    _clientWatermarks.clear();
    _watermark = 0;
    pushLog.clear();
  }

  /// Directly inject a change into the shared
  /// history (simulating a server-side change).
  /// Re-stamps the version with the next
  /// server-side watermark.
  void injectChange(SyncChange change) {
    _watermark++;
    _history.add(SyncChange(
      tableName: change.tableName,
      pk: change.pk,
      type: change.type,
      payload: change.payload,
      version: _watermark,
    ));
  }
}
