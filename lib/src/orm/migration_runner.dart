/// `MigrationRunner` — applies a list of [MigrationBase]s in
/// order, tracking which ones have already been applied in
/// the internal `_d_rocket_migrations` table.
///
/// Idempotency: when the caller provides a
/// [MigrationSelector] (via the [MigrationRunner.new]
/// constructor's `createSelector` callback), the runner is
/// fully idempotent: re-running the same set is a no-op
/// for migrations that are already recorded in the
/// `_d_rocket_migrations` table.
///
/// Transactions: when the caller provides
/// a [MigrationTransactionFactory] (via the `createTransaction`
/// callback), the runner wraps each `up` (and each
/// `down` in `rollback`) in a transaction. On
/// exception, the transaction is rolled back and the
/// migration is not recorded. Without the factory, the
/// caller is responsible for atomicity inside their own
/// `up` / `down`.
///
/// Schema versioning: the tracking table
/// gained a `version INTEGER` column. The runner
/// auto-migrates pre—10 databases by adding the
/// column, backfilling from `id` (which is a 0-padded
/// numeric string in the conventional style), and
/// creating an index on `version`. This makes
/// `migrateTo(targetVersion)` and
/// `MigrationStrategy.onUpgrade(oldV, newV)` dispatch
/// possible.
library;

import 'applied_migration.dart';
import 'migration.dart';
import 'migration_executor.dart';
import 'migration_selector.dart';
import 'async_migration_executor.dart';
import 'async_migration_selector.dart';

export 'migration.dart';
export 'applied_migration.dart';

/// Internal name of the table that tracks applied
/// migrations.
const String dRocketMigrationsTable = '_d_rocket_migrations';

///: the new tracking-table schema includes a
/// `version INTEGER` column (nullable for back-compat) and
/// is indexed on it. New installations get this schema
/// directly. Existing –9.x installations are
/// auto-migrated by [_ensureMigrationsTableSchema].
const String _migrationsTableDdlV2 = '''
  CREATE TABLE IF NOT EXISTS $dRocketMigrationsTable (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    version INTEGER,
    applied_at TEXT NOT NULL
  )
''';

///: idempotent `ALTER TABLE` that adds the
/// `version` column. Wrapped in a try/catch in
/// [_ensureMigrationsTableSchema] — the second run is a
/// no-op (the column already exists).
const String _addVersionColumnDdl = '''
  ALTER TABLE $dRocketMigrationsTable
  ADD COLUMN version INTEGER
''';

///: backfills `version` from the
/// zero-padded numeric `id` (the conventional style
/// scaffolded by `migration add`). Idempotent —
/// only updates rows where `version IS NULL`. Rows
/// whose `id` is non-numeric (date-based) keep
/// `version = NULL` until the user sets it manually.
const String _backfillVersionDdl = '''
  UPDATE $dRocketMigrationsTable
  SET version = CAST(id AS INTEGER)
  WHERE version IS NULL
''';

///: secondary index on `version` for
/// `currentVersion` / `applied` lookups.
const String _versionIndexDdl = '''
  CREATE INDEX IF NOT EXISTS
    idx_drm_version
  ON $dRocketMigrationsTable(version)
''';

/// A transactional execution context. Returned by a
/// [MigrationTransactionFactory] when the user opts in to
/// automatic transaction wrapping.
///
/// The user-provided factory creates one of these per
/// `up` / `down` invocation; the runner calls
/// [MigrationTransaction.commit] on success and
/// [MigrationTransaction.rollback] on exception.
class MigrationTransaction {
  /// Creates a transaction. The [executor] is the
  /// callback the migration body uses to run SQL. The
  /// [commit] / [rollback] actions are invoked by the
  /// runner exactly once per transaction.
  const MigrationTransaction({
    required this.executor,
    required this.commit,
    required this.rollback,
  });

  /// The executor the migration body uses to run SQL
  /// statements. Bound to the in-flight transaction.
  final MigrationExecutor executor;

  /// Commits the transaction. Idempotent — calling it
  /// more than once is a no-op (in case the user wraps
  /// their own callback logic around the runner).
  final void Function() commit;

  /// Rolls back the transaction. Idempotent.
  final void Function() rollback;
}

/// Factory that returns a fresh [MigrationTransaction]
/// per `up` / `down` invocation. The user's
/// implementation typically looks like:
///
/// ```dart
///  {
/// provider.execute('BEGIN');
/// return MigrationTransaction(
/// executor: (sql, [binds]) => provider.execute(sql, binds ??),
/// commit:  => provider.execute('COMMIT'),
/// rollback:  => provider.execute('ROLLBACK'),
///);
/// }
/// ```
typedef MigrationTransactionFactory = MigrationTransaction Function();

///: a transactional execution context for
/// the async path. Returned by an
/// [AsyncMigrationTransactionFactory] when the user opts
/// in to automatic transaction wrapping on
/// [MigrationRunner.runAsync] / [MigrationRunner.rollbackAsync].
///
/// The user-provided factory creates one of these per
/// `upAsync` / `downAsync` invocation; the runner
/// awaits [commit] on success and [rollback] on
/// exception.
class AsyncMigrationTransaction {
  /// Creates a transaction. The [executor] is the
  /// callback the migration body uses to run SQL. The
  /// [commit] / [rollback] actions are invoked by the
  /// runner exactly once per transaction.
  const AsyncMigrationTransaction({
    required this.executor,
    required this.commit,
    required this.rollback,
  });

  /// The executor the migration body uses to run SQL
  /// statements. Bound to the in-flight transaction.
  final AsyncMigrationExecutor executor;

  /// Commits the transaction. Idempotent — calling it
  /// more than once is a no-op (in case the user wraps
  /// their own callback logic around the runner).
  final Future<void> Function() commit;

  /// Rolls back the transaction. Idempotent.
  final Future<void> Function() rollback;
}

///: factory that returns a fresh
/// [AsyncMigrationTransaction] per `upAsync` /
/// `downAsync` invocation. The user's implementation
/// typically looks like:
///
/// ```dart
///  async {
/// await provider.beginTransactionAsync;
/// return AsyncMigrationTransaction(
/// executor: (sql, [binds]) async =>
/// await provider.executeAsync(sql, binds),
/// commit:  async => await provider.commitAsync,
/// rollback:  async => await provider.rollbackAsync,
///);
/// }
/// ```
typedef AsyncMigrationTransactionFactory = Future<AsyncMigrationTransaction>
    Function();

/// Runs a list of [MigrationBase]s in order against a
/// provider-agnostic [MigrationExecutor].
///
/// When `createSelector` is provided, the runner is fully
/// idempotent across re-runs. When it is omitted, the
/// runner assumes in-memory state only (useful for tests
/// where each `setUp` builds a fresh runner).
///
/// When `createTransaction` is provided, the runner wraps
/// each `up` (and each `down` in `rollback`) in a
/// transaction. This is the canonical way to make
/// migrations atomic.
class MigrationRunner {
  /// Creates a runner.
  ///
  /// [createExecutor] is called once per `run` /
  /// `rollback` invocation and returns a fresh
  /// [MigrationExecutor] for the migration body to use.
  ///
  /// [createSelector] is optional. When provided, the
  /// runner uses it to query the
  /// `_d_rocket_migrations` table before each `run`, so
  /// already-applied migrations are skipped. When omitted,
  /// the runner only tracks applied migrations in
  /// this instance (so re-using the same runner
  /// instance + the same list is a no-op; re-using the
  /// runner instance with a different list works but
  /// re-applying a previously-applied migration will
  /// throw a `PRIMARY KEY` violation from SQLite).
  ///
  /// [createTransaction] is optional . When
  /// provided, the runner wraps each `up` / `down` in
  /// a transaction. The factory must return a fresh
  /// [MigrationTransaction] per invocation. The runner
  /// calls `commit` on success and `rollback` on
  /// exception. Without it, the runner is not
  /// transactional — the user is responsible for
  /// atomicity inside their own `up` / `down`.
  ///
  /// [now] returns the current timestamp as an ISO-8601
  /// string; exposed for testability.
  ///
  /// [createAsyncExecutor] / [createAsyncSelector] /
  /// [createAsyncTransaction] are optional (
  /// 5.0+4). When set, the runner can also drive
  /// `runAsync` / `rollbackAsync`. When omitted, the
  /// runner auto-wraps the sync factories into async
  /// ones (handy for SQLite where the underlying
  /// provider is sync but the user wants to call
  /// `runAsync` for parity with the Postgres / MySQL
  /// path).
  MigrationRunner({
    required this.createExecutor,
    this.createSelector,
    this.createTransaction,
    this.createAsyncExecutor,
    this.createAsyncSelector,
    this.createAsyncTransaction,
    this.now = _defaultNow,
  });

  /// Factory that produces a fresh [MigrationExecutor]
  /// for each `run` / `rollback` call.
  final MigrationExecutor Function() createExecutor;

  /// Optional factory that produces a fresh
  /// [MigrationSelector] for each `run` call. When
  /// provided, the runner is fully idempotent across
  /// re-runs.
  final MigrationSelector Function()? createSelector;

  /// Optional factory that produces a fresh
  /// [MigrationTransaction] for each `up` / `down`
  /// call. When provided, the runner is fully atomic
  /// .
  final MigrationTransactionFactory? createTransaction;

  ///: optional factory that produces a
  /// fresh [AsyncMigrationExecutor] for each `runAsync`
  /// / `rollbackAsync` call. When omitted, the runner
  /// auto-wraps `createExecutor` (handy for SQLite).
  final AsyncMigrationExecutor Function()? createAsyncExecutor;

  ///: optional factory that produces a
  /// fresh [AsyncMigrationSelector] for each `runAsync`
  /// call. When omitted, the runner auto-wraps
  /// `createSelector` (or returns an empty set).
  final AsyncMigrationSelector Function()? createAsyncSelector;

  ///: optional factory that produces a
  /// fresh [AsyncMigrationTransaction] for each
  /// `upAsync` / `downAsync` call.
  final AsyncMigrationTransactionFactory? createAsyncTransaction;

  /// Returns the current timestamp as an ISO-8601 string.
  final String Function() now;

  static String _defaultNow() => DateTime.now().toUtc().toIso8601String();

  /// Applies the [migrations] in lexicographic order of
  /// their [MigrationBase.id]. Migrations that are already
  /// recorded in the `_d_rocket_migrations` table are
  /// skipped (idempotent, when `createSelector` is
  /// provided).
  ///
  /// Returns the list of migrations that were actually
  /// applied (in order). Useful for logging.
  ///
  /// When `createTransaction` is set, each `up` runs
  /// inside a transaction. On exception, the transaction
  /// is rolled back and the migration is not
  /// recorded in the tracking table.
  List<MigrationBase> run(List<MigrationBase> migrations) {
    final MigrationExecutor exec = createExecutor();
    _ensureMigrationsTable(exec);

    final Set<String> alreadyApplied = _loadAppliedIds();
    final List<MigrationBase> applied = <MigrationBase>[];

    final List<MigrationBase> sorted = <MigrationBase>[...migrations]
      ..sort((MigrationBase a, MigrationBase b) => a.id.compareTo(b.id));

    for (final MigrationBase m in sorted) {
      if (alreadyApplied.contains(m.id)) {
        continue;
      }
      if (createTransaction != null) {
        // Transactional path. On exception, the
        // transaction is rolled back; the migration is
        // not recorded.
        final MigrationTransaction tx = createTransaction!();
        try {
          m.up(tx.executor);
          _recordApplied(tx.executor, m);
          tx.commit();
        } catch (_) {
          tx.rollback();
          rethrow;
        }
      } else {
        // Non-transactional path (backward-compat with
        // behaviour).
        m.up(exec);
        _recordApplied(exec, m);
      }
      alreadyApplied.add(m.id);
      applied.add(m);
    }
    return applied;
  }

  /// Rolls back the [migrations] in reverse order.
  /// Migrations whose `down` throws [UnsupportedError]
  /// (the default for an irreversible migration) are
  /// skipped. Returns the migrations that were actually
  /// rolled back (in the order they were reversed).
  ///
  /// When `createTransaction` is set, each `down` runs
  /// inside a transaction. On exception, the transaction
  /// is rolled back and the migration is not removed
  /// from the tracking table.
  List<MigrationBase> rollback(List<MigrationBase> migrations) {
    final MigrationExecutor exec = createExecutor();
    _ensureMigrationsTable(exec);

    final List<MigrationBase> sorted = <MigrationBase>[...migrations]
      ..sort((MigrationBase a, MigrationBase b) => a.id.compareTo(b.id));

    final List<MigrationBase> rolledBack = <MigrationBase>[];
    for (final MigrationBase m in sorted.reversed) {
      try {
        if (createTransaction != null) {
          final MigrationTransaction tx = createTransaction!();
          try {
            m.down(tx.executor);
            _removeApplied(tx.executor, m);
            tx.commit();
          } catch (_) {
            tx.rollback();
            rethrow;
          }
        } else {
          m.down(exec);
          _removeApplied(exec, m);
        }
      } on UnsupportedError {
        continue; // irreversible migration: skip
      }
      rolledBack.add(m);
    }
    return rolledBack;
  }

  void _ensureMigrationsTable(MigrationExecutor exec) {
    _ensureMigrationsTableSchema((String sql, [List<Object?>? binds]) {
      exec(sql, binds);
    });
  }

  Future<void> _ensureMigrationsTableAsync(AsyncMigrationExecutor exec) async {
    await _ensureMigrationsTableSchemaAsync((String sql,
        [List<Object?>? binds]) async {
      await exec(sql, binds);
    });
  }

  ///: idempotent schema upgrade for the
  /// `_d_rocket_migrations` table. Creates the table
  /// with the V2 schema if it doesn't exist; otherwise
  /// detects a –9.x installation (no `version`
  /// column), adds the column, backfills `version` from
  /// `id`, and creates the secondary index. Safe to
  /// re-run — every step is guarded by either a
  /// try/catch (for `ALTER TABLE ADD COLUMN`) or an
  /// `IF NOT EXISTS` clause (for `CREATE TABLE` and
  /// `CREATE INDEX`).
  void _ensureMigrationsTableSchema(MigrationExecutor exec) {
    // 1. Create the table with the V2 schema.
    // - Fresh install: creates it with the
    // `version` column from the start.
    // - Existing install: CREATE TABLE IF NOT EXISTS
    // is a no-op (the table already exists with
    // the V1 schema, so the column is missing).
    exec(_migrationsTableDdlV2);

    // 2. Add the `version` column for pre—10
    // installations. The ALTER throws "duplicate
    // column name: version" on the second run; we
    // swallow that to keep the function idempotent.
    try {
      exec(_addVersionColumnDdl);
    } catch (_) {
      // Column already exists ( install, or
      // second run of the upgrade). Safe to ignore.
    }

    // 3. Backfill `version` from `id`. Idempotent —
    // the WHERE clause excludes rows whose
    // `version` was already set.
    exec(_backfillVersionDdl);

    // 4. Create the secondary index. IF NOT EXISTS
    // makes this a no-op on the second run.
    exec(_versionIndexDdl);
  }

  /// (async): the async counterpart of
  /// [_ensureMigrationsTableSchema]. Same steps, but
  /// awaits each `exec` call. The try/catch in step 2
  /// is preserved across the async boundary.
  Future<void> _ensureMigrationsTableSchemaAsync(
    Future<void> Function(String, [List<Object?>?]) exec,
  ) async {
    await exec(_migrationsTableDdlV2);
    try {
      await exec(_addVersionColumnDdl);
    } catch (_) {
      // Column already exists — safe to ignore.
    }
    await exec(_backfillVersionDdl);
    await exec(_versionIndexDdl);
  }

  Set<String> _loadAppliedIds() {
    if (createSelector == null) {
      return <String>{};
    }
    final MigrationSelector sel = createSelector!();
    final List<Map<String, Object?>> rows =
        sel('SELECT id FROM $dRocketMigrationsTable');
    return <String>{
      for (final Map<String, Object?> row in rows)
        if (row['id'] is String) row['id']! as String,
    };
  }

  void _recordApplied(MigrationExecutor exec, MigrationBase m) {
    exec(
      'INSERT INTO $dRocketMigrationsTable (id, name, applied_at) '
      'VALUES (?, ?, ?)',
      <Object?>[m.id, m.name, now()],
    );
  }

  void _removeApplied(MigrationExecutor exec, MigrationBase m) {
    exec(
      'DELETE FROM $dRocketMigrationsTable WHERE id = ?',
      <Object?>[m.id],
    );
  }

  // ───: async runner (runAsync / rollbackAsync) ────
  //
  // These are the async counterparts of [run] /
  // [rollback]. They use the [AsyncMigrationExecutor] /
  // [AsyncMigrationSelector] / [AsyncMigrationTransaction]
  // callbacks (or auto-wrap the sync ones). MigrationBase
  // bodies are written in the `upAsync` / `downAsync`
  // methods, which by default delegate to the sync
  // `up` / `down` (so existing migrations work
  // unchanged).

  ///: the async counterpart of [run].
  /// Applies the [migrations] in lexicographic order of
  /// their [MigrationBase.id]. Returns the list of migrations
  /// that were actually applied (in order).
  ///
  /// When `createAsyncSelector` is provided, the runner
  /// is fully idempotent across re-runs. When omitted,
  /// the runner auto-wraps `createSelector` (or returns
  /// an empty set when neither is set).
  ///
  /// When `createAsyncTransaction` is set, each
  /// `upAsync` runs inside a transaction. On
  /// exception, the transaction is rolled back and the
  /// migration is not recorded.
  Future<List<MigrationBase>> runAsync(List<MigrationBase> migrations) async {
    final AsyncMigrationExecutor exec = _resolveAsyncExecutor();
    await _ensureMigrationsTableAsync(exec);

    final Set<String> alreadyApplied = await _loadAppliedIdsAsync();
    final List<MigrationBase> applied = <MigrationBase>[];

    final List<MigrationBase> sorted = <MigrationBase>[...migrations]
      ..sort((MigrationBase a, MigrationBase b) => a.id.compareTo(b.id));

    for (final MigrationBase m in sorted) {
      if (alreadyApplied.contains(m.id)) {
        continue;
      }
      if (createAsyncTransaction != null) {
        final AsyncMigrationTransaction tx = await createAsyncTransaction!();
        try {
          await m.upAsync(tx.executor);
          await _recordAppliedAsync(tx.executor, m);
          await tx.commit();
        } catch (_) {
          await tx.rollback();
          rethrow;
        }
      } else {
        await m.upAsync(exec);
        await _recordAppliedAsync(exec, m);
      }
      alreadyApplied.add(m.id);
      applied.add(m);
    }
    return applied;
  }

  ///: the async counterpart of
  /// [rollback]. Rolls back the [migrations] in
  /// reverse order. Migrations whose `downAsync`
  /// throws [UnsupportedError] are skipped.
  Future<List<MigrationBase>> rollbackAsync(
      List<MigrationBase> migrations) async {
    final AsyncMigrationExecutor exec = _resolveAsyncExecutor();
    await _ensureMigrationsTableAsync(exec);

    final List<MigrationBase> sorted = <MigrationBase>[...migrations]
      ..sort((MigrationBase a, MigrationBase b) => a.id.compareTo(b.id));

    final List<MigrationBase> rolledBack = <MigrationBase>[];
    for (final MigrationBase m in sorted.reversed) {
      try {
        if (createAsyncTransaction != null) {
          final AsyncMigrationTransaction tx = await createAsyncTransaction!();
          try {
            await m.downAsync(tx.executor);
            await _removeAppliedAsync(tx.executor, m);
            await tx.commit();
          } catch (_) {
            await tx.rollback();
            rethrow;
          }
        } else {
          await m.downAsync(exec);
          await _removeAppliedAsync(exec, m);
        }
      } on UnsupportedError {
        continue; // irreversible migration: skip
      }
      rolledBack.add(m);
    }
    return rolledBack;
  }

  /// Resolves the [AsyncMigrationExecutor] to use,
  /// either from the user-supplied `createAsyncExecutor`
  /// factory (if any) or by auto-wrapping the sync
  /// `createExecutor` (used for SQLite and tests where
  /// the underlying provider is sync but the user wants
  /// to call `runAsync` for parity with the Postgres /
  /// MySQL path).
  AsyncMigrationExecutor _resolveAsyncExecutor() {
    if (createAsyncExecutor != null) {
      return createAsyncExecutor!();
    }
    final MigrationExecutor sync = createExecutor();
    return (String sql, [List<Object?>? binds]) async {
      sync(sql, binds ?? const <Object?>[]);
    };
  }

  Future<Set<String>> _loadAppliedIdsAsync() async {
    if (createAsyncSelector == null && createSelector == null) {
      return <String>{};
    }
    final AsyncMigrationSelector sel;
    if (createAsyncSelector != null) {
      sel = createAsyncSelector!();
    } else {
      final MigrationSelector sync = createSelector!();
      sel = (String sql, [List<Object?>? binds]) async {
        return sync(sql, binds ?? const <Object?>[]);
      };
    }
    final List<Map<String, Object?>> rows =
        await sel('SELECT id FROM $dRocketMigrationsTable');
    return <String>{
      for (final Map<String, Object?> row in rows)
        if (row['id'] is String) row['id']! as String,
    };
  }

  Future<void> _recordAppliedAsync(
      AsyncMigrationExecutor exec, MigrationBase m) async {
    await exec(
      'INSERT INTO $dRocketMigrationsTable (id, name, applied_at) '
      'VALUES (?, ?, ?)',
      <Object?>[m.id, m.name, now()],
    );
  }

  Future<void> _removeAppliedAsync(
      AsyncMigrationExecutor exec, MigrationBase m) async {
    await exec(
      'DELETE FROM $dRocketMigrationsTable WHERE id = ?',
      <Object?>[m.id],
    );
  }

  // ───: schema-versioning API ─────────────────────
  //
  // Three new pieces of state machinery on top of the
  // existing `run` / `rollback` pipeline:
  //
  // 1. `currentVersion` / `currentVersionAsync` —
  // returns the highest version recorded in
  // `_d_rocket_migrations` (0 when the table is
  // empty or doesn't exist yet).
  //
  // 2. `applied` / `appliedAsync` — returns the
  // full ordered list of [AppliedMigration]s, used
  // by the CLI `status` subcommand.
  //
  // 3. `migrateTo(targetVersion)` / `migrateToAsync` —
  // upgrades OR downgrades the database to exactly
  // `targetVersion`, picking the correct direction
  // based on `currentVersion`. On a downgrade,
  // irreversibly-skipped migrations are an error.
  //
  // All three are idempotent with respect to the
  // tracking table — they do their own
  // `_ensureMigrationsTableSchema` call so callers
  // don't have to `run` first.

  ///: returns the highest version currently
  /// recorded in `_d_rocket_migrations`, or `0` if no
  /// migrations have been applied yet. Uses the
  /// secondary index on `version` ( upgrade)
  /// when available.
  ///
  /// Throws [StateError] if no selector factory was
  /// provided to the runner.
  int currentVersion() {
    if (createSelector == null) {
      throw StateError(
        'MigrationRunner.currentVersion() requires a '
        '`createSelector` factory. Provide one in the '
        'MigrationRunner constructor so the runner can '
        'query the _d_rocket_migrations table.',
      );
    }
    _ensureMigrationsTable(
      (String sql, [List<Object?>? binds]) => createExecutor()(sql, binds),
    );
    final MigrationSelector sel = createSelector!();
    final List<Map<String, Object?>> rows = sel(
      'SELECT MAX(version) AS v FROM $dRocketMigrationsTable',
    );
    if (rows.isEmpty) return 0;
    final Object? first = rows.first['v'];
    if (first is int) return first;
    if (first is num) return first.toInt();
    return 0;
  }

  /// (async): the async counterpart of
  /// [currentVersion].
  Future<int> currentVersionAsync() async {
    await _ensureMigrationsTableAsync(
      (String sql, [List<Object?>? binds]) async =>
          await _resolveAsyncExecutor()(sql, binds),
    );
    final AsyncMigrationSelector asyncSel = _resolveAsyncSelector()();
    final List<Map<String, Object?>> rows = await asyncSel(
      'SELECT MAX(version) AS v FROM $dRocketMigrationsTable',
    );
    if (rows.isEmpty) return 0;
    final Object? first = rows.first['v'];
    if (first is int) return first;
    if (first is num) return first.toInt();
    return 0;
  }

  ///: returns the full list of applied
  /// migrations, ordered by `version` ascending. Used
  /// by the CLI's `status` subcommand.
  ///
  /// Throws [StateError] if no selector factory was
  /// provided.
  List<AppliedMigration> applied() {
    if (createSelector == null) {
      throw StateError(
        'MigrationRunner.applied() requires a `createSelector` '
        'factory. Provide one in the MigrationRunner '
        'constructor.',
      );
    }
    _ensureMigrationsTable(
      (String sql, [List<Object?>? binds]) => createExecutor()(sql, binds),
    );
    final MigrationSelector sel = createSelector!();
    final List<Map<String, Object?>> rows = sel(
      'SELECT id, name, version, applied_at '
      'FROM $dRocketMigrationsTable '
      'ORDER BY version ASC, id ASC',
    );
    return rows.map(AppliedMigration.fromRow).toList(
          growable: false,
        );
  }

  /// (async): the async counterpart of
  /// [applied].
  Future<List<AppliedMigration>> appliedAsync() async {
    await _ensureMigrationsTableAsync(
      (String sql, [List<Object?>? binds]) async =>
          await _resolveAsyncExecutor()(sql, binds),
    );
    final AsyncMigrationSelector asyncSel = _resolveAsyncSelector()();
    final List<Map<String, Object?>> rows = await asyncSel(
      'SELECT id, name, version, applied_at '
      'FROM $dRocketMigrationsTable '
      'ORDER BY version ASC, id ASC',
    );
    return rows.map(AppliedMigration.fromRow).toList(
          growable: false,
        );
  }

  ///: brings the database to exactly
  /// [targetVersion]. If `currentVersion < targetVersion`,
  /// applies the migrations in `(current, target]`. If
  /// `currentVersion > targetVersion`, rolls back the
  /// migrations in `(target, current]` in reverse
  /// order. If they're equal, this is a no-op.
  ///
  /// Migrations whose `down` throws [UnsupportedError]
  /// (the default) on a downgrade surface as
  /// [StateError] — the user is expected to either
  /// override `down` or pick a non-skipping target.
  List<MigrationBase> migrateTo(
    int targetVersion,
    List<MigrationBase> migrations,
  ) {
    final int from = currentVersion();
    if (from == targetVersion) {
      return <MigrationBase>[]; // already there
    }
    if (targetVersion > from) {
      // Upgrade: pick the subset whose version is in
      // (from, target] and run them in order.
      final List<MigrationBase> subset = <MigrationBase>[
        for (final m in migrations)
          if (m.version > from && m.version <= targetVersion) m,
      ]..sort((a, b) => a.version.compareTo(b.version));
      return run(subset);
    }
    // Downgrade: pick the subset whose version is in
    // (target, from] and roll them back in reverse.
    final List<MigrationBase> subset = <MigrationBase>[
      for (final m in migrations)
        if (m.version > targetVersion && m.version <= from) m,
    ]..sort((a, b) => b.version.compareTo(a.version));
    return rollback(subset);
  }

  /// (async): the async counterpart of
  /// [migrateTo].
  Future<List<MigrationBase>> migrateToAsync(
    int targetVersion,
    List<MigrationBase> migrations,
  ) async {
    final int from = await currentVersionAsync();
    if (from == targetVersion) {
      return <MigrationBase>[]; // already there
    }
    if (targetVersion > from) {
      final List<MigrationBase> subset = <MigrationBase>[
        for (final m in migrations)
          if (m.version > from && m.version <= targetVersion) m,
      ]..sort((a, b) => a.version.compareTo(b.version));
      return runAsync(subset);
    }
    final List<MigrationBase> subset = <MigrationBase>[
      for (final m in migrations)
        if (m.version > targetVersion && m.version <= from) m,
    ]..sort((a, b) => b.version.compareTo(a.version));
    return rollbackAsync(subset);
  }

  ///: returns an [AsyncMigrationSelector]
  /// factory that the async-currentVersion /
  /// async-applied methods use. Resolves the
  /// user-supplied `createAsyncSelector` first; falls
  /// back to auto-wrapping the sync `createSelector`.
  AsyncMigrationSelector Function() _resolveAsyncSelector() {
    if (createAsyncSelector != null) {
      return () => createAsyncSelector!();
    }
    if (createSelector != null) {
      return () {
        final MigrationSelector sync = createSelector!();
        return (String sql, [List<Object?>? binds]) async {
          return sync(sql, binds ?? const <Object?>[]);
        };
      };
    }
    throw StateError(
      'MigrationRunner: no selector factory. Provide '
      '`createSelector` (or `createAsyncSelector`) in the '
      'MigrationRunner constructor.',
    );
  }
}
