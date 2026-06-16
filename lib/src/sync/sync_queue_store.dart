// Persistent backing store for the sync queue.
//
// Before 1.1.1 the pending sync queue was a
// `List<SyncChange>` held in memory inside
// `DbContext`. If the app crashed or the device
// lost power between `saveChangesAsync()` and
// `syncAsync()`, every change committed locally
// since the last successful sync was lost — a
// critical data-loss risk for any app that needs
// to sync clinical, financial, or audit data.
//
// `SyncQueueStore` is a thin SQLite-backed
// replacement. The queue is a single table,
// `d_rocket_sync_queue`, in the same database as
// the user data (so it picks up SQLCipher
// encryption for free when the main DB is
// encrypted). All writes are issued through the
// shared [AsyncQueryProvider], so an INSERT runs
// inside whatever transaction the caller is in —
// typically the same transaction as the data
// change that produced the `SyncChange`. This
// gives us atomicity: either the data change
// AND the queue entry commit, or neither does.
//
// The store is **internal**: the public API
// (`DbContext.saveChangesAsync`, `syncAsync`,
// `pendingSyncChanges`) is unchanged. Existing
// callers get persistence for free; no opt-in
// flag, no new parameter.

import 'dart:async';
import 'dart:convert';

import '../orm/async_query_provider.dart';
import 'sync_change.dart';
import 'sync_change_type.dart';

/// Backing store for the persistent sync queue.
///
/// Not exported from the package barrel — the
/// store is an implementation detail of
/// [DbContext]. Use [DbContext.pendingSyncChanges]
/// to read the queue from application code.
class SyncQueueStore {
  /// Creates a store that writes to [provider]'s
  /// underlying connection. The provider is
  /// expected to be the same one that handles the
  /// data writes, so INSERTs into the queue table
  /// participate in the caller's transaction.
  ///
  /// [maxQueueSize] caps the on-disk size of the
  /// queue. When the cap is exceeded, the oldest
  /// rows are dropped (with a warning logged via
  /// `print` — change to a proper log sink in a
  /// future release). The default of 10,000 rows
  /// is conservative; a row carries a JSON payload
  /// that is typically a few hundred bytes, so
  /// the cap maps to a few MB on disk.
  SyncQueueStore({
    required AsyncQueryProvider provider,
    this.maxQueueSize = 10000,
  }) : _provider = provider;

  final AsyncQueryProvider _provider;
  final int maxQueueSize;

  bool _initialised = false;

  ///: name of the table. Exposed as a
  /// constant so tests and the documentation
  /// reference the same string.
  static const String tableName = 'd_rocket_sync_queue';

  /// helper: creates the table on first use. Idempotent.
  Future<void> _ensureTable() async {
    if (_initialised) return;
    await _provider.executeAsync('''
      CREATE TABLE IF NOT EXISTS $tableName (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        pk TEXT NOT NULL,
        change_type TEXT NOT NULL,
        payload_json TEXT,
        version INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    _initialised = true;
  }

  /// Inserts [change] into the queue. Must be
  /// called inside a transaction that is also the
  /// transaction the data write happened in (or in
  /// its own transaction if there is no data
  /// write). Returns the new row id.
  Future<int> enqueue(SyncChange change) async {
    await _ensureTable();
    final String? payloadJson = change.payload == null
        ? null
        : jsonEncode(change.payload);
    await _provider.executeAsync(
      'INSERT INTO $tableName '
      '(table_name, pk, change_type, payload_json, version, created_at) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[
        change.tableName,
        change.pk,
        change.type.name,
        payloadJson,
        change.version,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
    final int id = await _provider.lastInsertRowIdAsync();
    await _trimToCap();
    return id;
  }

  /// Returns all queued changes in insertion
  /// order. Used by the `DbContext` on startup to
  /// rehydrate the in-memory cache, and by
  /// `syncAsync` if the cache is empty (e.g. the
  /// process was restarted before any local
  /// `saveChangesAsync` happened).
  Future<List<SyncChange>> loadAll() async {
    await _ensureTable();
    final List<Object?> rows = await _provider.selectAsync(
      'SELECT table_name, pk, change_type, payload_json, version '
      'FROM $tableName ORDER BY id ASC',
    );
    final List<SyncChange> out = <SyncChange>[];
    for (final Object? row in rows) {
      final Map<String, Object?> m = row! as Map<String, Object?>;
      final String typeName = m['change_type']! as String;
      final Map<String, Object?>? payload =
          m['payload_json'] == null
              ? null
              : jsonDecode(m['payload_json']! as String)
                  as Map<String, Object?>;
      out.add(
        SyncChange(
          tableName: m['table_name']! as String,
          pk: m['pk']! as String,
          type: SyncChangeType.values.firstWhere(
            (SyncChangeType t) => t.name == typeName,
          ),
          payload: payload,
          version: m['version']! as int,
        ),
      );
    }
    return out;
  }

  /// Deletes every row in the queue. Called from
  /// [DbContext.syncAsync] after a successful
  /// round-trip. Must be called in a transaction
  /// (so the delete is atomic with the caller's
  /// other bookkeeping).
  Future<void> clearAll() async {
    await _ensureTable();
    await _provider.executeAsync('DELETE FROM $tableName');
  }

  /// Returns the number of rows currently in the
  /// queue. Cheap (no row materialisation).
  Future<int> count() async {
    await _ensureTable();
    final List<Object?> rows = await _provider.selectAsync(
      'SELECT COUNT(*) AS n FROM $tableName',
    );
    if (rows.isEmpty) return 0;
    final Object? first = rows.first;
    final Map<String, Object?> m = first! as Map<String, Object?>;
    return (m['n'] as int?) ?? 0;
  }

  /// helper: if the table has more than
  /// [maxQueueSize] rows, drop the oldest ones
  /// (keeping the most recent `maxQueueSize`).
  /// Logs a warning to stdout when trimming
  /// happens — the queue should be considered
  /// near-full at this point and the next
  /// `syncAsync` is overdue.
  Future<void> _trimToCap() async {
    final int n = await count();
    if (n <= maxQueueSize) return;
    final int toDrop = n - maxQueueSize;
    // Print rather than log: d_rocket does not
    // own a logging abstraction yet, and the
    // warning is informational, not actionable
    // at the call site. A future release can
    // route this through a `LogSink` interface
    // once one exists.
    // ignore: avoid_print
    print(
      '[d_rocket] SyncQueueStore: dropping '
      '$toDrop oldest queued change(s); the cap '
      'is $maxQueueSize and sync has not been '
      'keeping up.',
    );
    await _provider.executeAsync(
      'DELETE FROM $tableName WHERE id IN ('
      'SELECT id FROM $tableName ORDER BY id ASC LIMIT ?'
      ')',
      <Object?>[toDrop],
    );
  }
}
