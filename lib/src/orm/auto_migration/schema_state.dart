// Schema state: the on-disk table that stores the
// last applied [SchemaSnapshot].
//
// The auto-migration system uses a single-row
// key-value table to keep the snapshot of the
// schema that is currently in force. The row is
// overwritten on every successful auto-migration
// run; a fresh install finds an empty table and
// runs the migration in "first install" mode
// (apply every CREATE TABLE / CREATE INDEX).
//
// The table is intentionally separate from
// `_d_rocket_migrations` (the table that tracks
// hand-written `MigrationBase` runs). The two
// tables coexist: hand-written migrations go
// through the existing MigrationRunner, and
// auto-migrations go through SchemaState. They
// never share data.

import 'dart:async';

import '../async_query_provider.dart';
import 'schema_snapshot.dart';

///: name of the on-disk table that
/// stores the last applied schema snapshot. A
/// single row, keyed by `id = 1`.
const String schemaStateTableName = 'd_rocket_schema_state';

///: schema for the [schemaStateTableName]
/// table. A single row keyed by `id = 1`. The
/// `CHECK (id = 1)` constraint guards against
/// accidental multi-row inserts.
const String schemaStateTableDdl = '''
  CREATE TABLE IF NOT EXISTS $schemaStateTableName (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    schema_json TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
''';

///: thin wrapper around the
/// `d_rocket_schema_state` table. The wrapper
/// is created by [AutoMigrator] and is not
/// exported from the package barrel — application
/// code interacts with it indirectly via
/// `Db.pendingSchemaDiff()` and the
/// `Db.open(autoMigrate: true)` flag.
class SchemaState {
  /// Creates a [SchemaState] backed by [provider].
  /// The provider is expected to be the same
  /// connection that handles the user's data writes
  /// (so the snapshot read/write participates in
  /// the caller's transaction).
  SchemaState({required AsyncQueryProvider provider})
      : _provider = provider;

  final AsyncQueryProvider _provider;
  bool _initialised = false;

  ///: creates the on-disk table on
  /// first use. Idempotent — safe to call from
  /// every method, the cost is one
  /// `CREATE TABLE IF NOT EXISTS` per process
  /// (and zero on subsequent calls thanks to the
  /// [_initialised] guard).
  Future<void> _ensureTable() async {
    if (_initialised) return;
    await _provider.executeAsync(schemaStateTableDdl);
    _initialised = true;
  }

  ///: returns the last applied snapshot,
  /// or `null` if no auto-migration has ever been
  /// recorded (i.e. fresh install, or a runtime
  /// upgrade from a 1.1.x install that did not
  /// have the auto-migration system at all).
  Future<SchemaSnapshot?> read() async {
    await _ensureTable();
    final List<Object?> rows = await _provider.selectAsync(
      'SELECT schema_json FROM $schemaStateTableName WHERE id = 1',
    );
    if (rows.isEmpty) return null;
    final Map<String, Object?> m = rows.first! as Map<String, Object?>;
    final String? encoded = m['schema_json'] as String?;
    if (encoded == null || encoded.isEmpty) return null;
    return SchemaSnapshot.decode(encoded);
  }

  ///: persists [snapshot] as the new
  /// last-applied snapshot. The `id = 1` row is
  /// overwritten (`INSERT OR REPLACE`).
  ///
  /// `updated_at` is the current UTC time as an
  /// ISO-8601 string.
  ///
  /// Must be called inside the same transaction
  /// as the auto-migration `up` calls. The
  /// `INSERT OR REPLACE` is atomic per row, so
  /// the snapshot is always either the old one
  /// (if the transaction rolls back) or the new
  /// one (if it commits) — there is no window
  /// where the snapshot is ahead of the schema.
  Future<void> write(SchemaSnapshot snapshot) async {
    await _ensureTable();
    await _provider.executeAsync(
      'INSERT OR REPLACE INTO $schemaStateTableName '
      '(id, schema_json, updated_at) VALUES (1, ?, ?)',
      <Object?>[
        snapshot.encode(),
        DateTime.now().toUtc().toIso8601String(),
      ],
    );
  }

  ///: clears the stored snapshot.
  /// Used by tests and by the
  /// `debugResetAutoMigrationState` test-only
  /// helper. Not exported from the barrel.
  Future<void> clear() async {
    await _ensureTable();
    await _provider.executeAsync(
      'DELETE FROM $schemaStateTableName WHERE id = 1',
    );
  }
}
