import 'sync_change.dart';

/// A batch of [SyncChange]s.
///
/// `clientId` identifies the local context (so the
/// server can echo back changes for OTHER clients
/// to receive). `since` is the last watermark we
/// saw (so the server knows what to send back).
class SyncEnvelope {
  const SyncEnvelope({
    required this.clientId,
    required this.since,
    required this.changes,
  });

  /// Unique client id (e.g. a UUID assigned to the
  /// device on first launch).
  final String clientId;

  /// Last watermark we synced (0 if first sync).
  final int since;

  /// Batch of changes.
  final List<SyncChange> changes;

  /// JSON serialisation.
  Map<String, Object?> toJson() => <String, Object?>{
        'clientId': clientId,
        'since': since,
        'changes': <Object?>[for (final SyncChange c in changes) c.toJson()],
      };

  /// Inverse of [toJson].
  static SyncEnvelope fromJson(Map<String, Object?> json) {
    final List<Object?> raw = json['changes']! as List<Object?>;
    return SyncEnvelope(
      clientId: json['clientId']! as String,
      since: json['since']! as int,
      changes: <SyncChange>[
        for (final Object? c in raw)
          SyncChange.fromJson(c! as Map<String, Object?>),
      ],
    );
  }
}
