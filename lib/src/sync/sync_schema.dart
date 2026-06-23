/// 2.0.0 — schema migration sync.
///
/// When the server's schema version differs
/// from the client's, the client should:
///
/// 1. Receive the remote changes.
/// 2. Check if the remote schema version is
///    newer than the local schema version.
/// 3. If yes, run a migration (or refuse the
///    sync with a clear error).
///
/// This file provides the abstractions. The
/// actual migration logic is application-
/// specific (it's a callback the user
/// provides).
library;

/// The current schema version. The caller
/// tracks this (e.g. in a `d_rocket_meta`
/// table).
class SyncSchemaVersion {
  /// Creates a [SyncSchemaVersion] from a
  /// numeric version (e.g. `1`, `2`).
  const SyncSchemaVersion(this.value)
      : assert(value >= 0, 'version must be non-negative');

  /// The numeric value.
  final int value;

  /// The initial version (used by new
  /// databases).
  static const SyncSchemaVersion initial = SyncSchemaVersion(0);

  /// `true` if this version is newer than
  /// [other] (i.e. the local is older than
  /// the remote, and a migration is needed).
  bool isNewerThan(SyncSchemaVersion other) => value > other.value;

  /// The next version (used after a
  /// migration).
  SyncSchemaVersion bumped() => SyncSchemaVersion(value + 1);

  @override
  bool operator ==(Object other) =>
      other is SyncSchemaVersion && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'SyncSchemaVersion($value)';
}

/// The result of a schema check during sync.
enum SyncSchemaResult {
  /// The schemas are compatible; proceed.
  ok,

  /// The local schema is older; migration
  /// needed.
  needsMigration,

  /// The local schema is newer; the server
  /// is out of date. This is unusual (we
  /// usually only check on the client side).
  serverOutOfDate,
}

/// Checks the local and remote schema
/// versions and returns a [SyncSchemaResult].
SyncSchemaResult checkSchema({
  required SyncSchemaVersion local,
  required SyncSchemaVersion remote,
}) {
  if (remote.isNewerThan(local)) return SyncSchemaResult.needsMigration;
  if (local.isNewerThan(remote)) return SyncSchemaResult.serverOutOfDate;
  return SyncSchemaResult.ok;
}
