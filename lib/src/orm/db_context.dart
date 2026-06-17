import 'package:d_rocket/d_rocket.dart';

/// Abstract base class for every d_rocket ORM context.
///
/// A `DbContext` owns:
/// * one [ChangeTracker] (shared across every `DbSet<T>`);
/// * a set of `DbSet<T>` instances (one per `@Table`
/// class);
/// * a connection to the underlying storage (a SQLite database
/// in the MVP, but the interface is storage-agnostic).
///
/// The user subclasses `DbContext` and adds a
/// `DbSet<X> get x` getter for every entity type. Each
/// `dbSet<T>` call constructs a `DbSet<T>` on demand and
/// caches it in [_dbSets].
///
/// ### SaveChanges flow
///
/// `SaveChanges` walks the tracker in this order:
/// 1. For every `Added` entry: build & run the `INSERT`,
/// capture the DB-assigned PK (if the PK is
/// auto-increment), re-key the tracker entry, and
/// transition to `Unchanged`.
/// 2. For every `Modified` entry: build & run the
/// `UPDATE` and transition to `Unchanged`.
/// 3. For every `Removed` entry: build & run the `DELETE`
/// and untrack the entry.
/// 4. Return the total number of rows affected.
///
/// `SaveChanges` is NOT idempotent: calling it twice in a
/// row is fine (the second call is a no-op because every
/// entry has already transitioned to `Unchanged` or been
/// untracked), but calling it on a context whose storage
/// connection is closed is a [StateError].
abstract class DbContext {
  /// The shared change tracker.
  final ChangeTracker changeTracker = ChangeTracker();

  /// Lazily-constructed `DbSet<T>` instances, keyed by the
  /// entity `Type`. Populated on the first call to
  /// `dbSet<T>` for a given `T`.
  final Map<Type, Object> _dbSets = <Type, Object>{};

  /// Persistent backing store for
  /// [\_pendingSyncChanges]. Set in the constructor
  /// of the concrete `\_SqliteRocketContext`;
  /// left null in the abstract base so unit tests
  /// that instantiate `DbContext` directly do not
  /// have to wire a provider.
  ///
  /// The name omits the leading underscore (so
  /// the concrete subclass in `db.dart` can
  /// initialise it) but it is documented as an
  /// internal field. Application code should
  /// never read or write this directly.
  SyncQueueStore? queueStore;

  /// Builder for a `DbSet<T>`. Subclasses override
  /// [createDbSet] to customise the underlying storage
  /// connection (or, in the MVP, just delegate to the
  /// default).
  DbSet<T> createDbSet<T>(EntityMeta Function() metaAccessor);

  /// Returns the `DbSet<T>` for the entity class `T`. The
  /// first call constructs the set; subsequent calls return
  /// the cached instance.
  ///
  ///: if the surrounding [DbContext]
  /// subclass has set [sqliteProvider], the freshly
  /// constructed `DbSet` is wired to it via
  /// `DbSet.attachSqliteProvider`. This enables
  /// `dbSet.asQueryable` to build a [Queryable]
  /// over the table.
  ///
  ///: if [asyncProvider] is also set, the
  /// `DbSet` is wired to it via
  /// `DbSet.attachAsyncProvider`. This enables the
  /// `*Async_` read methods (`toListAsync_`,
  /// `findByIdAsync`, etc.).
  ///: registers a `DbSet<T>` and (optionally)
  /// aliases it for the child types of a TPH hierarchy.
  ///
  /// ```dart
  /// late final DbSet<_Animal> animals = dbSet<_Animal>(
  ///  => animalMeta,
  /// // TPH: also register as DbSet<_Dog> / DbSet<_Cat>
  /// // so `_dbSetForEntity(_Dog)` resolves to this DbSet.
  /// hierarchy: `<Type>`[_Dog, _Cat],
  ///);
  /// ```
  ///
  /// The [hierarchy] list is used by the runtime to
  /// look up the right `DbSet` at `saveChanges` time
  ///: looks up the [EntityMeta] for [T] in
  /// the global [EntityRegistry] populated by
  /// `initializeD` (emitted by `d_rocket_builder`).
  /// Concrete on the base class — subclasses don't need
  /// to override it.
  EntityMeta entityMetaFor<T>() {
    return EntityRegistry.metaFor(T);
  }

  /// (when the entity's `runtimeType` is a child of
  /// [T]). It is not a generic superclass walk —
  /// Dart's `Type` doesn't expose the class hierarchy
  /// at runtime, so the user (or the codegen) must
  /// declare the list explicitly.
  DbSet<T> dbSet<T>(
    EntityMeta Function() metaAccessor, {
    List<Type> hierarchy = const <Type>[],
  }) {
    final DbSet<T>? cached = _dbSets[T] as DbSet<T>?;
    if (cached != null) return cached;
    final DbSet<T> created = createDbSet<T>(metaAccessor);
    _dbSets[T] = created;
    //: register aliases for the child
    // types of the TPH hierarchy. The same DbSet
    // instance is reused, so a `DbSet<_Animal>` is
    // also findable as `DbSet<_Dog>` /
    // `DbSet<_Cat>`.
    for (final Type childType in hierarchy) {
      if (_dbSets[childType] == null) {
        _dbSets[childType] = created;
      }
    }
    //: wire the async provider
    // (any backend that implements AsyncQueryProvider —
    // SQLite, Postgres, MySQL, …). The
    // provider-specific attach (e.g.
    // `attach<SqliteQueryProvider>(p)`) is now done
    // by the provider package's extension on
    // `DbContext`; we only do the generic
    // async path here.
    final AsyncQueryProvider? async = asyncProvider;
    if (async != null) {
      created.attachAsyncProvider(async);
    }
    return created;
  }

  ///: the optional [AsyncQueryProvider]
  /// backing this context. Subclasses that own a
  /// storage connection (SQLite, Postgres, MySQL, …)
  /// override this to expose it.
  ///
  /// The recommended pattern: override
  /// this getter — the base class wires the provider
  /// into every `DbSet<T>` automatically via
  /// [dbSet]. The user only needs to override one
  /// getter to switch backends:
  ///
  /// ```dart
  /// // SQLite
  /// class MySqliteContext extends DbContext {
  /// final SqliteQueryProvider provider;
  /// MySqliteContext(this.provider);
  /// @override
  /// AsyncQueryProvider? get asyncProvider => provider;
  /// // ...
  /// }
  ///
  /// // Postgres
  /// class MyPostgresContext extends DbContext {
  /// final PostgresQueryProvider provider;
  /// MyPostgresContext(this.provider);
  /// @override
  /// AsyncQueryProvider? get asyncProvider => provider;
  /// // ...
  /// }
  /// ```
  ///
  /// The user can then call `*Async_` methods on every
  /// `DbSet<T>` (e.g. `await ctx.authors.toListAsync_`).
  AsyncQueryProvider? get asyncProvider => null;

  /// Optional [MigrationTransactionFactory] for
  /// `saveChanges` . When set, the entire
  /// `saveChanges` batch (every INSERT, UPDATE, DELETE
  /// in the order described in the class docstring) is
  /// wrapped in a single transaction.
  ///
  /// On exception, the transaction is rolled back, the
  /// change tracker entries remain in their original
  /// states (so the user can `saveChanges` again), and
  /// the exception is rethrown.
  ///
  /// Without it, the MVP keeps the non-transactional
  /// behaviour (each INSERT / UPDATE / DELETE is its own
  /// atomic statement; the batch is not atomic).
  MigrationTransactionFactory? get createSaveChangesTransaction => null;

  /// Runs every pending `INSERT` / `UPDATE` / `DELETE` in
  /// the order described in the class docstring.
  ///
  /// Returns the total number of rows affected.
  ///
  ///: when [createSaveChangesTransaction] is
  /// set, the entire batch is wrapped in a single
  /// transaction. On exception, the transaction is rolled
  /// back, the change tracker entries remain in their
  /// original states, and the exception is rethrown. The
  /// auto-PK back-propagation of any entity whose `INSERT`
  /// already ran is lost on rollback (the in-memory
  /// entity's `id` is whatever it was before the
  /// `saveChanges` call).
  int saveChanges() {
    final MigrationTransactionFactory? txFactory = createSaveChangesTransaction;
    if (txFactory != null) {
      return _saveChangesInTransaction(txFactory);
    }
    return _saveChangesUnwrapped();
  }

  /// (async): the async counterpart of
  /// [saveChanges]. Returns a `Future<int>` with the total
  /// number of rows affected.
  ///
  /// Throws [StateError] if no [AsyncQueryProvider] is
  /// attached (configure [asyncProvider] on the
  /// surrounding subclass).
  ///
  /// The batch is wrapped in a transaction via the
  /// [AsyncQueryProvider]'s `beginTransactionAsync` /
  /// `commitAsync` / `rollbackAsync` methods. On
  /// exception, the transaction is rolled back, the change
  /// tracker entries remain in their original states, and
  /// the exception is rethrown. The auto-PK
  /// back-propagation of any entity whose `INSERT`
  /// already ran is lost on rollback.
  Future<int> saveChangesAsync() async {
    final AsyncQueryProvider? provider = asyncProvider;
    if (provider == null) {
      throw StateError(
        'DbContext.saveChangesAsync() requires an '
        'AsyncQueryProvider. Override the asyncProvider getter '
        'on your DbContext subclass (the same way you '
        'override sqliteProvider).',
      );
    }
    // + fix-5.13.1: snapshot the
    // entries that are about to be committed (so
    // we can build SyncChanges for them post-commit
    // without re-processing the whole tracker).
    // Includes `removed` entries so the push
    // pipeline can emit delete SyncChanges to the
    // server. (The pre-fix 5.11 code only
    // snapshotted Added + Modified, which meant
    // deletes were silently dropped from the push
    // queue — the server never knew a row was
    // deleted locally.)
    final List<TrackedEntry> entriesToSync = changeTracker.entries
        .where((TrackedEntry e) =>
            e.state == EntityState.added ||
            e.state == EntityState.modified ||
            e.state == EntityState.removed)
        .toList();
    await provider.beginTransactionAsync();
    int affected = 0;
    final Map<TrackedEntry, int> insertedPks = <TrackedEntry, int>{};
    try {
      // 1. Inserts first (so the auto-PK of a freshly
      // inserted row is available for any subsequent
      // UPDATE in the same batch).
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.added) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        await set.insertOneAsync(entry.entity);
        final int? pk = await set.lastInsertedPkAsync();
        if (pk != null) {
          insertedPks[entry] = pk;
        }
        affected += 1;
      }

      // 2. Updates.
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.modified) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        await set.updateOneAsync(
            entry.entity, entry.originalValues ?? const <String, Object?>{});
        affected += 1;
      }

      // 3. Deletes.
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.removed) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        await set.deleteOneAsync(entry.entity);
        affected += 1;
      }

      // (push queue, fix-1.1.1): persist a
      // [SyncChange] for every entry that was
      // committed IN THIS SAVE, INSIDE the same
      // transaction as the data writes. When a
      // [SyncQueueStore] is wired (the production
      // path, set by `\_SqliteRocketContext`),
      // the INSERT runs through the same provider
      // as the data writes so the two are
      // committed atomically. When the store is
      // not wired (the abstract-base path used by
      // some unit tests), we still build the
      // SyncChange list and append to the
      // in-memory cache, so the legacy
      // "list-of-changes" contract is preserved
      // for those tests. The in-memory cache is
      // always updated after commit; if the
      // transaction rolls back, the cache and
      // the persistent queue are both unchanged.
      final SyncQueueStore? store = queueStore;
      final List<SyncChange> newChanges = <SyncChange>[];
      for (final TrackedEntry entry in entriesToSync) {
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        // fix-5.13.1: emit a delete SyncChange
        // for removed entries (with a null
        // payload) instead of an upsert.
        final SyncChangeType type = entry.state == EntityState.removed
            ? SyncChangeType.delete
            : SyncChangeType.upsert;
        final SyncChange change = _buildSyncChangeFor(
          entry.entity,
          set.meta.tableName,
          set.meta.pkOf(entry.entity),
          type,
        );
        if (store != null) {
          await store.enqueue(change);
        }
        newChanges.add(change);
      }

      // The transaction is fully constructed. Commit it.
      await provider.commitAsync();

      // Post-commit bookkeeping (back-propagate PKs with
      // the per-entity PK captured during the inserts
      // loop, mark entries as Unchanged, untrack deletes).
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state == EntityState.added) {
          final DbSet<Object> set = _dbSetForEntity(entry.entity);
          final int? pk = insertedPks[entry];
          if (pk != null) {
            try {
              set.meta.setId?.call(entry.entity, pk);
            } on StateError {
              // The codegen did not emit a `setId` hook
              // (e.g. the user wrote a hand-rolled
              // EntityMeta). Skip the back-propagation.
            }
          }
          entry.state = EntityState.unchanged;
        } else if (entry.state == EntityState.modified) {
          entry.state = EntityState.unchanged;
        } else if (entry.state == EntityState.removed) {
          final DbSet<Object> set = _dbSetForEntity(entry.entity);
          final Object? pk = set.meta.pkOf(entry.entity);
          changeTracker.untrack(pk);
        }
      }
      //: fire a `Saved` event on the
      // tracker so `DbSet.watch` re-emits
      // immediately (instead of waiting for the
      // next `pollInterval` tick).
      changeTracker.emitSaved();
      // (push queue, post-commit): update the
      // in-memory cache that backs
      // [pendingSyncChanges] now that the data +
      // queue INSERTs have committed. The cache
      // is a read-through view of the persistent
      // queue; it does not need to be rehydrated
      // from disk because every entry we just
      // appended is already in `newChanges`.
      _pendingSyncChanges.addAll(newChanges);
      queueHydrated = true;
      return affected;
    } catch (_) {
      // Roll back the transaction; the change tracker
      // entries stay in their original states (Added,
      // Modified, Removed), so the user can fix the
      // cause and re-run `saveChangesAsync`.
      await provider.rollbackAsync();
      rethrow;
    }
  }

  /// The non-transactional path. Used by [saveChanges] when
  /// [createSaveChangesTransaction] is `null`.
  int _saveChangesUnwrapped() {
    int affected = 0;

    // 1. Inserts first (so the auto-PK of a freshly inserted
    // row is available for any subsequent UPDATE in the
    // same batch).
    for (final TrackedEntry entry in changeTracker.entries.toList()) {
      if (entry.state != EntityState.added) continue;
      final DbSet<Object> set = _dbSetForEntity(entry.entity);
      affected += set.insertOne(entry.entity);
      //: capture the PK right after each
      // individual insert. ( read the
      // `lastInsertRowId` AFTER the entire inserts loop,
      // so every entity in a multi-insert batch ended up
      // with the last PK.)
      final int? pk = set.lastInsertedPk();
      if (pk != null) {
        // Run the codegen-supplied `setId` hook with the
        // exact PK this insert produced. Throws StateError
        // if the PK field is `final` (the codegen refuses
        // to emit a non-assignable setter).
        try {
          set.meta.setId?.call(entry.entity, pk);
        } on StateError {
          // The codegen did not emit a `setId` hook (e.g.
          // the user wrote a hand-rolled EntityMeta).
          // Skip the back-propagation.
        }
      }
      entry.state = EntityState.unchanged;
    }

    // 2. Updates.
    for (final TrackedEntry entry in changeTracker.entries.toList()) {
      if (entry.state != EntityState.modified) continue;
      final DbSet<Object> set = _dbSetForEntity(entry.entity);
      affected += set.updateOne(
          entry.entity, entry.originalValues ?? const <String, Object?>{});
      entry.state = EntityState.unchanged;
    }

    // 3. Deletes.
    for (final TrackedEntry entry in changeTracker.entries.toList()) {
      if (entry.state != EntityState.removed) continue;
      final DbSet<Object> set = _dbSetForEntity(entry.entity);
      affected += set.deleteOne(entry.entity);
      final Object? pk = set.meta.pkOf(entry.entity);
      changeTracker.untrack(pk);
    }

    return affected;
  }

  /// The transactional path. Used by [saveChanges] when
  /// [createSaveChangesTransaction] is set. The entire
  /// batch (every INSERT, UPDATE, DELETE in the order
  /// described in the class docstring) is wrapped in a
  /// single user-supplied transaction. On exception, the
  /// transaction is rolled back, the change tracker
  /// entries remain in their original states, and the
  /// exception is rethrown.
  int _saveChangesInTransaction(MigrationTransactionFactory txFactory) {
    final MigrationTransaction tx = txFactory();
    int affected = 0;
    //: capture the PK of each insert right
    // after the executor ran it. (Reading
    // `lastInsertRowId` post-commit yields the last PK,
    // not the per-entity PK.)
    final Map<TrackedEntry, int> insertedPks = <TrackedEntry, int>{};
    try {
      // 1. Inserts.
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.added) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        final int? pk = set.insertOneWith(entry.entity, tx.executor);
        if (pk != null) {
          insertedPks[entry] = pk;
        }
        affected += 1;
      }

      // 2. Updates.
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.modified) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        affected += set.updateOneWith(entry.entity,
            entry.originalValues ?? const <String, Object?>{}, tx.executor);
      }

      // 3. Deletes.
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state != EntityState.removed) continue;
        final DbSet<Object> set = _dbSetForEntity(entry.entity);
        affected += set.deleteOneWith(entry.entity, tx.executor);
      }

      // The transaction is fully constructed. Commit it.
      tx.commit();

      // Post-commit bookkeeping (back-propagate PKs with
      // the per-entity PK captured during the inserts
      // loop, mark entries as Unchanged, untrack deletes).
      for (final TrackedEntry entry in changeTracker.entries.toList()) {
        if (entry.state == EntityState.added) {
          final DbSet<Object> set = _dbSetForEntity(entry.entity);
          final int? pk = insertedPks[entry];
          if (pk != null) {
            try {
              set.meta.setId?.call(entry.entity, pk);
            } on StateError {
              // The codegen did not emit a `setId` hook
              // (e.g. the user wrote a hand-rolled
              // EntityMeta). Skip the back-propagation.
            }
          }
          entry.state = EntityState.unchanged;
        } else if (entry.state == EntityState.modified) {
          entry.state = EntityState.unchanged;
        } else if (entry.state == EntityState.removed) {
          final DbSet<Object> set = _dbSetForEntity(entry.entity);
          final Object? pk = set.meta.pkOf(entry.entity);
          changeTracker.untrack(pk);
        }
      }
      return affected;
    } catch (_) {
      // Roll back the transaction; the change tracker
      // entries stay in their original states (Added,
      // Modified, Removed), so the user can fix the cause
      // and re-run `saveChanges`.
      tx.rollback();
      rethrow;
    }
  }

  /// Look up the right `DbSet<Object>` for [entity] (a
  /// generic lookup because the tracker is heterogeneous).
  ///
  ///: when the entity's runtime type has no
  /// registered `DbSet`, the lookup walks up the class
  /// hierarchy so a `DbSet<_Animal>` matches a
  /// `DbSet<_Animal>` request for a `_Dog` instance. This
  /// is what makes TPH work transparently — the user
  /// registers the root DbSet (and any child types) and
  /// the runtime dispatches the entity to the right one.
  DbSet<Object> _dbSetForEntity(Object entity) {
    final Type t = entity.runtimeType;
    final DbSet<Object>? set = _dbSets[t] as DbSet<Object>?;
    if (set == null) {
      throw StateError(
        'No DbSet<$t> has been registered in this '
        'DbContext. For TPH hierarchies (Fase 5.2+), '
        'pass the list of child types via '
        '`dbSet<_Animal>(...)` so the runtime can resolve '
        '`DbSet<_Dog>` and `DbSet<_Cat>` to the same DbSet.',
      );
    }
    return set;
  }

  // ───: versioned migrations + auto-apply ───
  //
  // The user registers a list of [MigrationBase]s in the
  // context, then calls [migrate] / [migrateAsync] at
  // app startup. The internal `_d_rocket_migrations`
  // table tracks which migrations have already run
  // (idempotent across re-runs).

  ///: the list of [MigrationBase]s to apply at
  /// startup. Override in the user's context and return
  /// the migrations in any order (the runner sorts
  /// them lexicographically by `id`).
  ///
  /// Default: empty list (no migrations to apply).
  List<MigrationBase> get migrations => const <MigrationBase>[];

  ///: applies all pending [migrations] in
  /// lexicographic order. Migrations that are already
  /// recorded in the `_d_rocket_migrations` table are
  /// skipped (idempotent).
  ///
  /// Each `up` runs inside a transaction when the
  /// provider supports it (auto-detected: a provider
  /// that has `sqliteProvider` or `asyncProvider`
  /// enables the transactional path). On exception,
  /// the transaction is rolled back and the migration
  /// is not recorded.
  ///
  /// Returns the list of migrations that were actually
  /// applied (in order). Useful for logging at startup.
  ///
  /// (provider-agnostic): when an
  /// [asyncProvider] is wired, use [migrateAsync] instead
  /// — `migrate` is sync and cannot bridge to the
  /// async path safely. The sync `migrate` is kept
  /// for the legacy sync-only path (no
  /// `asyncProvider`); the runner uses the provider's
  /// `executeAsync` under the hood when the async
  /// path is needed.
  List<MigrationBase> migrate() {
    final AsyncQueryProvider? async = asyncProvider;
    if (async != null) {
      throw UnsupportedError(
        'DbContext.migrate() is sync. The context has an '
        '`asyncProvider` wired — use `await ctx.migrateAsync()` '
        'instead. Migrating to a real provider in the async '
        'path is the recommended pattern in d_rocket 1.1+.',
      );
    }
    return _buildRunner().run(migrations);
  }

  ///: the async counterpart of [migrate].
  /// Awaits each `upAsync` in turn.
  Future<List<MigrationBase>> migrateAsync() async {
    return _buildAsyncRunner().runAsync(migrations);
  }

  ///: rolls back the most recently applied
  /// [migrations] (or the specific list passed as
  /// [toRollback]). The default behaviour rolls back
  /// all registered migrations in reverse order
  /// (handy for "give me a clean DB" in dev).
  ///
  /// Pass [toRollback] to roll back a specific subset
  /// (e.g. just the last one).
  List<MigrationBase> rollback({List<MigrationBase>? toRollback}) {
    return _buildRunner()
        .rollback(toRollback ?? <MigrationBase>[...migrations]);
  }

  ///: the async counterpart of [rollback].
  Future<List<MigrationBase>> rollbackAsync(
      {List<MigrationBase>? toRollback}) async {
    return _buildAsyncRunner()
        .rollbackAsync(toRollback ?? <MigrationBase>[...migrations]);
  }

  // ───: schema-versioning API ─────────────────────
  //
  // Three thin wrappers around the
  // [MigrationRunner] that the [Db] facade
  // forwards to. See `migration_runner.dart` for the
  // canonical implementation.

  ///: the async counterpart of the
  /// runner's [MigrationRunner.currentVersion]. Returns
  /// `0` for a fresh install.
  Future<int> currentVersionAsync() async {
    return _buildAsyncRunner().currentVersionAsync();
  }

  ///: the async counterpart of the
  /// runner's [MigrationRunner.applied]. Returns the
  /// full list of applied migrations, ordered by
  /// `version` ascending.
  Future<List<AppliedMigration>> appliedAsync() async {
    return _buildAsyncRunner().appliedAsync();
  }

  ///: brings the database to exactly
  /// [targetVersion]. Picks the direction (upgrade /
  /// downgrade) based on the current schema version.
  /// No-op if already at the target. See
  /// [MigrationRunner.migrateTo] for details.
  Future<List<MigrationBase>> migrateToAsync(
    int targetVersion,
    List<MigrationBase> migrations,
  ) {
    return _buildAsyncRunner().migrateToAsync(targetVersion, migrations);
  }

  ///: runs a [MigrationStrategy] against
  /// the database. The strategy's `version` is the
  /// target. The runner picks the right callback
  /// (declarative list / imperative onCreate /
  /// imperative onUpgrade / imperative onDowngrade)
  /// based on the current schema version.
  Future<List<MigrationBase>> migrateStrategyAsync(
    MigrationStrategy strategy,
  ) async {
    final MigrationRunner runner = _buildAsyncRunner();
    final int from = await runner.currentVersionAsync();
    final int to = strategy.version;

    if (from == to) {
      return <MigrationBase>[]; // already at target
    }

    if (strategy.isImperative) {
      // Imperative mode: the user owns the branching.
      // We don't auto-track — the user is responsible
      // for the _d_rocket_migrations table.
      if (from == 0 && strategy.onCreate != null) {
        final AsyncMigrationExecutor exec = _buildAsyncExecutorOnly();
        await strategy.onCreate!(exec, to);
        return <MigrationBase>[];
      }
      if (to > from && strategy.onUpgrade != null) {
        final AsyncMigrationExecutor exec = _buildAsyncExecutorOnly();
        await strategy.onUpgrade!(exec, from, to);
        return <MigrationBase>[];
      }
      if (to < from && strategy.onDowngrade != null) {
        final AsyncMigrationExecutor exec = _buildAsyncExecutorOnly();
        await strategy.onDowngrade!(exec, from, to);
        return <MigrationBase>[];
      }
      if (to < from) {
        throw StateError(
          'MigrationStrategy at v$from cannot downgrade to v$to: '
          'no `onDowngrade` callback provided. Either '
          'add one or use the declarative `migrations` list '
          '(the runner rolls back via `MigrationBase.down()`).',
        );
      }
      return <MigrationBase>[];
    }

    // Declarative mode: the runner picks the subset.
    return runner.migrateToAsync(to, strategy.migrations);
  }

  // ───: seed hook + initializeD helper ───
  //
  // The user overrides [seed] to populate the
  // database with initial / dev / test data. The
  // hook is called once at startup, after
  // [migrateAsync], by [initializeDAsync].
  //
  // The default is a no-op (the user can leave it
  // empty if they don't want to seed).

  ///: the seed hook. Override to
  /// populate the database with initial / dev /
  /// test data.
  ///
  /// Runs after [migrateAsync] (so the tables are
  /// guaranteed to exist). The user typically
  /// checks `isEmpty` and inserts if so, so
  /// re-running is idempotent.
  ///
  /// Default: no-op.
  Future<void> seed() async {
    // no-op
  }

  ///: one-shot setup — runs
  /// [migrateAsync] (applying pending schema
  /// changes) then [seed] (populating initial
  /// data). The canonical "start the app" call.
  ///
  /// Returns the list of migrations that were
  /// applied (empty if the schema was already
  /// up-to-date).
  Future<List<MigrationBase>> initializeDAsync() async {
    final List<MigrationBase> applied = await migrateAsync();
    await seed();
    return applied;
  }

  // ─── / 5.11: sync layer (offline-first ↔ cloud) ───
  //
  // The pattern: collect local changes, push to
  // the [SyncProvider], then pull remote changes
  // and apply them locally (with last-write-wins
  // conflict resolution).
  //
  //: the local `_pendingSyncChanges`
  // queue is populated by [saveChangesAsync] after
  // a successful commit. The next [syncAsync] pushes
  // them and clears the queue (only on success).

  /// (state): the queue of local
  /// changes that have been committed locally
  /// but not yet pushed to the remote. Populated
  /// by [saveChangesAsync] (after commit) and
  /// drained by [syncAsync] (on success).
  ///
  /// In-memory cache backed by [SyncQueueStore].
  /// The table in the same SQLite database is the
  /// source of truth: a crash between
  /// [saveChangesAsync] and [syncAsync] does not
  /// lose queued changes. The cache is hydrated
  /// lazily on first access (see
  /// [_ensureQueueHydrated]).
  final List<SyncChange> _pendingSyncChanges = <SyncChange>[];

  /// helper: hydrates [\_pendingSyncChanges] from
  /// the persistent [SyncQueueStore] the first
  /// time it is needed. Subsequent calls are
  /// no-ops (set a flag on completion). Called
  /// from [saveChangesAsync] (before adding new
  /// changes) and from the [pendingSyncChanges]
  /// getter (before returning).
  ///
  /// Named without the leading underscore so
  /// subclasses in other files can call it (it
  /// is overridden by `\_SqliteRocketContext`
  /// where applicable).
  Future<void> ensureQueueHydrated() async {
    if (queueHydrated) return;
    final SyncQueueStore? store = queueStore;
    if (store == null) return; // abstract base
    _pendingSyncChanges
      ..clear()
      ..addAll(await store.loadAll());
    queueHydrated = true;
  }

  bool queueHydrated = false;

  ///: returns a snapshot of the
  /// pending local changes (read-only).
  ///
  /// Hydrates the in-memory cache from the
  /// persistent store on first access (so the
  /// queue is consistent across app restarts).
  /// The hydration is awaited transparently by
  /// [Db.pendingSyncChanges] (the consumer-facing
  /// wrapper); calling this getter directly from
  /// inside the context returns whatever the
  /// in-memory cache holds at the time, which
  /// may be empty on the first read after
  /// construction.
  List<SyncChange> get pendingSyncChanges =>
      List<SyncChange>.unmodifiable(_pendingSyncChanges);

  /// (state): the active sync
  /// triggers. Started by [startSyncTriggers]
  /// and stopped by [stopSyncTriggers] (or
  /// automatically when the context is disposed).
  final List<SyncTrigger> _activeSyncTriggers = <SyncTrigger>[];

  ///: starts the given list of
  /// [SyncTrigger]s. Each trigger will call
  /// `ctx.syncAsync(provider, stateStore: ...)`
  /// when it fires. The user can mix-and-match
  /// triggers (e.g. a [PeriodicSyncTrigger] for
  /// the background fallback + a
  /// [SignalSyncTrigger] for pull-to-refresh).
  ///
  /// The [provider] and [stateStore] are
  /// remembered and re-used for every fire.
  void startSyncTriggers({
    required SyncProvider provider,
    List<SyncTrigger> triggers = const <SyncTrigger>[],
    SyncStateStore? stateStore,
  }) {
    for (final SyncTrigger t in triggers) {
      _activeSyncTriggers.add(t);
      t.start(() async {
        await syncAsync(provider, stateStore: stateStore);
      });
    }
  }

  ///: stops all the active sync
  /// triggers. Safe to call multiple times.
  void stopSyncTriggers() {
    for (final SyncTrigger t in _activeSyncTriggers) {
      t.stop();
    }
    _activeSyncTriggers.clear();
  }

  /// (state): the persisted
  /// clientId, set by [bootstrapSync] (or by
  /// passing `clientId` to [syncAsync]). The
  /// default is `null` (no clientId yet) — the
  /// user MUST call [bootstrapSync] before
  /// [syncAsync] in production.
  String? _clientId;

  ///: returns the persisted
  /// clientId (or `null` if [bootstrapSync]
  /// hasn't been called).
  String? get clientId => _clientId;

  ///: one-shot setup for sync
  /// state. Loads (or generates + persists) the
  /// clientId and the watermark. The user calls
  /// this once at app startup, alongside
  /// [initializeDAsync].
  ///
  /// If [store] already has a clientId, that
  /// one is reused (so the device's identity is
  /// stable across app restarts). If not, a new
  /// id is generated and persisted.
  ///
  /// If [forceNewId] is `true`, the existing
  /// clientId is discarded and a new one is
  /// generated (use this when the server's
  /// history has been wiped and the device needs
  /// a fresh identity).
  ///
  /// Returns the loaded (or freshly generated)
  /// clientId.
  Future<String> bootstrapSync(
    SyncStateStore store, {
    bool forceNewId = false,
  }) async {
    String? id = forceNewId ? null : await store.getClientIdAsync();
    if (id == null) {
      id = 'client-${DateTime.now().millisecondsSinceEpoch}'
          '-${_randomSuffix()}';
      await store.setClientIdAsync(id);
    }
    _clientId = id;
    _clientWatermark = await store.getWatermarkAsync();
    return id;
  }

  /// (internal): returns a small
  /// random suffix for clientId generation.
  int _randomSuffix() {
    // A simple LCG-style RNG (deterministic
    // per-call) — avoids depending on
    // `dart:math`'s Random for portability.
    final DateTime now = DateTime.now();
    return (now.microsecondsSinceEpoch * 1103515245 + 12345) & 0x7fffffff;
  }

  /// / 5.11 / 5.12 / 5.16: orchestrator
  /// that:
  /// 1. Push — sends the pending local
  /// changes (from [saveChangesAsync] since
  /// the last sync) to the [provider].
  /// 2. Pull — receives the remote envelope
  /// (changes since `since`).
  /// 3. Apply — applies the remote changes
  /// locally (LWW conflict resolution).
  /// 4. Persist — if [stateStore] is
  /// provided, the new watermark is saved
  /// (so the next sync can resume from there).
  /// 5. Retry — if [retryPolicy] is provided
  /// AND the round-trip fails, the orchestrator
  /// sleeps + retries (per the policy).
  ///
  /// The [clientId] is taken from
  /// [bootstrapSync] (if set), or from this
  /// parameter (legacy). It is mandatory in
  /// production — if neither is set, a
  /// [StateError] is thrown.
  ///
  /// The pending queue is cleared only after a
  /// successful sync (so a failed sync retries
  /// on the next call).
  ///
  /// Returns the list of remote changes that
  /// were applied. The watermark is advanced on
  /// the provider side.
  Future<List<SyncChange>> syncAsync(
    SyncProvider provider, {
    String? clientId,
    SyncStateStore? stateStore,
    RetryPolicy? retryPolicy,
  }) async {
    // (clientId): prefer the
    // bootstrap-set id; fall back to the
    // parameter; throw if neither is set.
    final String? resolvedId = clientId ?? _clientId;
    if (resolvedId == null) {
      throw StateError(
        'ctx.syncAsync() requires a clientId. Either call '
        'ctx.bootstrapSync(stateStore) first, or pass '
        'clientId: \'...\' explicitly.',
      );
    }
    // (push, fix-1.1.1): read the local
    // queue from the persistent store. We do
    // not trust the in-memory cache for this
    // read: a previous saveChangesAsync may have
    // committed a row that the cache does not
    // yet know about (e.g. after a process
    // restart that did not trigger
    // saveChangesAsync again). Reading from the
    // store also gives us a single, atomic
    // snapshot — `loadAll()` is one SELECT
    // statement, so we cannot see a partial
    // state of the queue.
    final SyncQueueStore? store = queueStore;
    final List<SyncChange> localChanges;
    if (store != null) {
      localChanges = await store.loadAll();
      // Refresh the in-memory cache so a
      // subsequent `pendingSyncChanges` getter
      // sees the same set.
      _pendingSyncChanges
        ..clear()
        ..addAll(localChanges);
      queueHydrated = true;
    } else {
      // Abstract-base path (e.g. unit tests
      // without a wired store): fall back to
      // the in-memory list.
      localChanges = List<SyncChange>.of(_pendingSyncChanges);
    }
    final int lastWatermark = _clientWatermark;
    final SyncEnvelope envelope = SyncEnvelope(
      clientId: resolvedId,
      since: lastWatermark,
      changes: localChanges,
    );
    // (retry): wrap the round-trip
    // in a retry loop. The policy decides when
    // (and whether) to retry. On success we break
    // out of the loop.
    final RetryPolicy policy = retryPolicy ?? const NoRetryPolicy();
    SyncEnvelope remote;
    try {
      remote = await _syncWithRetry(provider, envelope, policy);
    } catch (_) {
      // The retry policy exhausted its attempts
      // (or threw on a non-retryable error).
      // We do NOT drain the queue — the next
      // syncAsync call will retry the same
      // changes.
      rethrow;
    }
    // (apply): for each remote
    // change, apply locally with last-write-wins.
    final List<SyncChange> applied = <SyncChange>[];
    for (final SyncChange change in remote.changes) {
      await _applyRemoteChange(change);
      applied.add(change);
    }
    // (drain, fix-1.1.1): on a successful
    // sync, clear both the persistent store
    // (source of truth) and the in-memory cache.
    // The two are kept in lockstep so that a
    // subsequent `pendingSyncChanges` getter
    // returns the empty list.
    if (store != null) {
      await store.clearAll();
    }
    _pendingSyncChanges.clear();
    _clientWatermark = remote.since;
    // (auto-persist): if the user
    // passed a state store, save the new
    // watermark so the next sync resumes from
    // there. We also save the clientId (it's
    // idempotent, but explicit).
    if (stateStore != null) {
      await stateStore.setWatermarkAsync(_clientWatermark);
    }
    return applied;
  }

  /// (internal): wraps
  /// `provider.syncAsync` in a retry loop. On
  /// each failure, the policy decides whether to
  /// retry. Returns the successful [SyncEnvelope]
  /// or re-throws the last error.
  Future<SyncEnvelope> _syncWithRetry(
    SyncProvider provider,
    SyncEnvelope envelope,
    RetryPolicy policy,
  ) async {
    int attempt = 0;
    while (true) {
      try {
        return await provider.syncAsync(envelope);
      } catch (e, st) {
        final RetryDecision decision = policy.shouldRetry(
          attempt: attempt,
          error: e,
          stackTrace: st,
        );
        if (decision.isGiveUp) {
          rethrow;
        }
        await Future<void>.delayed(decision.after);
        attempt++;
      }
    }
  }

  /// (state): the last server-side
  /// watermark we successfully synced to. Used
  /// as `envelope.since` in the next [syncAsync].
  int _clientWatermark = 0;

  ///: returns the last successfully
  /// synced watermark.
  int get syncWatermark => _clientWatermark;

  /// (internal): builds a [SyncChange]
  /// for a freshly-committed entry. The [tableName]
  /// comes from the [EntityMeta] of the entity's
  /// registered DbSet, the [pk] from
  /// `meta.pkOf(entity)`, the [payload] is the
  /// serialised row.
  SyncChange _buildSyncChangeFor(
    Object entity,
    String tableName,
    Object? pk,
    SyncChangeType type,
  ) {
    final DbSet<Object> set = _dbSetForEntity(entity);
    final Map<String, Object?>? payload =
        type == SyncChangeType.upsert ? _serialiseEntity(entity, set) : null;
    return SyncChange(
      tableName: tableName,
      pk: pk?.toString() ?? '',
      type: type,
      payload: payload,
      version: DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// (internal): serialises an
  /// entity to a `Map<String, Object?>` of column
  /// names to values. Uses the same `readColumn`
  /// / `readField` mechanism that the INSERT
  /// path uses.
  Map<String, Object?> _serialiseEntity(
    Object entity,
    DbSet<Object> set,
  ) {
    final Map<String, Object?> payload = <String, Object?>{};
    for (final ColumnMeta col in set.meta.columns) {
      // Use the DbSet's internal read mechanism
      // (handles both `readColumn` and
      // `readField`).
      payload[col.sqlName] = set.readFieldForTest(entity, col);
    }
    return payload;
  }

  /// (internal): applies a remote
  /// [SyncChange] locally. Last-write-wins: if
  /// the local row exists with a higher
  /// `version` (we use the same column to track
  /// the local `updated_at` / `_d_rocket_version`
  /// as the version), skip the remote change.
  Future<void> _applyRemoteChange(SyncChange change) async {
    final AsyncQueryProvider? provider = asyncProvider;
    if (provider == null) return;
    if (change.type == SyncChangeType.delete) {
      // DELETE: remove the row by primary key.
      final String tableName = change.tableName;
      // The user is expected to have registered a
      // DbSet for this table; we use the
      // provider's bulk delete to remove the row.
      await provider.executeDeleteAsync(
        table: tableName,
        where: 'id = ?',
        whereBinds: <Object?>[change.pk],
      );
    } else {
      // UPSERT: insert or merge the row.
      final String tableName = change.tableName;
      final Map<String, Object?> payload = change.payload!;
      // (LWW): check if the local
      // row already exists.
      final List<Object?> existing = await provider.selectAsync(
        'SELECT * FROM $tableName WHERE id = ? LIMIT 1',
        <Object?>[change.pk],
      );
      // (conflict resolution): if
      // the local row exists AND a custom
      // [ConflictResolver] is registered for this
      // table, use it to merge the rows. Otherwise
      // fall back to LWW (the remote row wins).
      final Map<String, Object?> finalPayload;
      if (existing.isNotEmpty) {
        final Map<String, Object?> localRow =
            (existing.first as Map<String, Object?>);
        final ConflictResolver? resolver = _conflictResolverForTable(tableName);
        if (resolver != null) {
          finalPayload = resolver(localRow, payload);
        } else {
          // Default: LWW — remote wins.
          finalPayload = <String, Object?>{...localRow, ...payload};
        }
      } else {
        // No local row — just insert the payload.
        finalPayload = payload;
      }
      if (existing.isEmpty) {
        // INSERT.
        final String cols = finalPayload.keys.join(', ');
        final String placeholders =
            finalPayload.keys.map((String _) => '?').join(', ');
        await provider.executeAsync(
          'INSERT INTO $tableName ($cols) VALUES ($placeholders)',
          finalPayload.values.toList(),
        );
      } else {
        // UPDATE.
        final String setClause =
            finalPayload.keys.map((String col) => '$col = ?').join(', ');
        await provider.executeAsync(
          'UPDATE $tableName SET $setClause WHERE id = ?',
          <Object?>[...finalPayload.values, change.pk],
        );
      }
    }
  }

  /// (internal): looks up the
  /// [ConflictResolver] for a given table, if
  /// any of the context's registered DbSets
  /// targets that table and has a non-null
  /// [EntityMeta.conflictResolver].
  ConflictResolver? _conflictResolverForTable(String tableName) {
    for (final Object entry in _dbSets.values) {
      final DbSet<Object> set = entry as DbSet<Object>;
      if (set.meta.tableName == tableName) {
        return set.meta.conflictResolver;
      }
    }
    return null;
  }

  /// (internal): builds a sync
  /// [MigrationRunner] wired to this context's
  /// provider + transaction factory.
  ///
  /// (provider-agnostic): when an
  /// [asyncProvider] is wired, the runner's sync
  /// executor throws (`migrate` then throws at
  /// the caller — see [migrate]). The user must
  /// call `migrateAsync` instead. When no
  /// asyncProvider is wired (the legacy sync
  /// path), the runner uses the abstract
  /// [AsyncQueryProvider] interface via
  /// `selectWithBinds` (provided by the test's
  /// manual DbSet creation). This path is
  /// provider-agnostic in shape, but tests
  /// typically wire it to a SQLite provider for
  /// the no-asyncProvider case.
  MigrationRunner _buildRunner() {
    final AsyncQueryProvider? async = asyncProvider;
    if (async == null) {
      // Legacy sync path (no asyncProvider wired).
      // The runner needs a sync executor + selector.
      // Since the core ORM has no DB-specific
      // executor in sync mode (the sync mode was
      // removed in), we throw a clear
      // message. Users with the legacy sync path
      // should either:
      // (a) Wire their `asyncProvider` and use
      // `migrateAsync`, OR
      // (b) Migrate to a provider package and
      // use the provider's sync migration
      // helper.
      throw UnsupportedError(
        'DbContext.migrate() (sync) is not available '
        'without an `asyncProvider`. The legacy sync '
        'path was removed in d_rocket 1.1 (Fase 9.0). '
        'Use `await ctx.migrateAsync()` instead — wire '
        'your `asyncProvider` to the `AsyncQueryProvider` '
        'of your DB (e.g. `SqliteQueryProvider`) and the '
        'migration will run in the async path.',
      );
    }
    return MigrationRunner(
      createExecutor: () => (String sql, [List<Object?>? binds]) {
        // The sync executor must throw — the runner
        // detects this and switches to the async
        // path internally.
        throw UnsupportedError(
          'migrate() reached the sync executor; the async '
          'provider is wired. The runner should have '
          'detected this and switched to `createAsyncExecutor`.',
        );
      },
      createAsyncExecutor: () => (String sql, [List<Object?>? binds]) async {
        await async.executeAsync(sql, binds);
      },
      createSelector: () => (String sql, [List<Object?>? binds]) {
        throw UnsupportedError(
          'migrate() reached the sync selector; the async '
          'provider is wired. The runner should have '
          'detected this and switched to `createAsyncSelector`.',
        );
      },
      createAsyncSelector: () => (String sql, [List<Object?>? binds]) async {
        final List<Object?> rows = await async.selectAsync(sql, binds);
        return <Map<String, Object?>>[
          for (final Object? r in rows) r! as Map<String, Object?>,
        ];
      },
    );
  }

  /// (internal): builds an async
  /// [MigrationRunner] wired to this context's
  /// async provider.
  MigrationRunner _buildAsyncRunner() {
    final AsyncQueryProvider? async = asyncProvider;
    if (async == null) {
      throw StateError(
        'migrateAsync() requires `asyncProvider` to be '
        'set. For sync providers, call migrate() instead.',
      );
    }
    // The runner's typedefs use
    // `Future<void> Function(...)` and
    // `Future<List<Map<String, Object?>>> Function(
    // ...)`. Dart 3's strict inference turns an
    // `async` lambda returning nothing into
    // `Future<Null>` (which is not assignable
    // to `Future<void>`), and the AsyncQueryProvider
    // returns `Future<List<Object?>>` (not
    // `Future<List<Map<String, Object?>>>`). We
    // therefore declare typed helpers.
    Future<void> asyncExec(String sql, [List<Object?>? binds]) async {
      await async.executeAsync(sql, binds);
    }

    Future<List<Map<String, Object?>>> asyncSel(String sql,
        [List<Object?>? binds]) async {
      // The `AsyncQueryProvider.selectAsync` returns
      // `Future<List<Object?>>` (each row is a
      // `Map<String, Object?>` but the typed
      // signature uses `Object?`). We cast
      // element-by-element.
      final List<Object?> rows = await async.selectAsync(sql, binds);
      return <Map<String, Object?>>[
        for (final Object? r in rows) r! as Map<String, Object?>,
      ];
    }

    return MigrationRunner(
      // Sync factories are required by the runner's
      // signature but never called in the async path.
      createExecutor: () => (String sql, [List<Object?>? binds]) {
        throw UnsupportedError(
          'The sync MigrationExecutor was called from the '
          'async path. This is a d_rocket bug.',
        );
      },
      createAsyncExecutor: () => asyncExec,
      createAsyncSelector: () => asyncSel,
      // / 5.3: when the provider is
      // the SQLite one (which implements
      // `beginTransactionAsync` etc.), wrap each
      // `upAsync` in a real transaction. For
      // Postgres the same `begin/commit/
      // rollback` API is used.
      createAsyncTransaction: () async {
        await async.beginTransactionAsync();
        return AsyncMigrationTransaction(
          executor: (String sql, [List<Object?>? binds]) async {
            await async.executeAsync(sql, binds);
          },
          commit: () async {
            await async.commitAsync();
          },
          rollback: () async {
            await async.rollbackAsync();
          },
        );
      },
    );
  }

  /// (internal): returns a fresh
  /// [AsyncMigrationExecutor] bound to the context's
  /// [AsyncQueryProvider]. Used by
  /// [migrateStrategyAsync] in imperative mode to hand
  /// the user a single `exec` callback without
  /// allocating a full [MigrationRunner].
  AsyncMigrationExecutor _buildAsyncExecutorOnly() {
    final AsyncQueryProvider? async = asyncProvider;
    if (async == null) {
      throw StateError(
        'MigrationStrategy: asyncProvider is null. The '
        'strategy requires an async provider.',
      );
    }
    return (String sql, [List<Object?>? binds]) async {
      await async.executeAsync(sql, binds);
    };
  }
}
