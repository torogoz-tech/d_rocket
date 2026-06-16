/// The user-facing entry point for d_rocket's SQLite engine.
///
/// SQLite-First for Flutter: this is the
/// only entry point a user needs. No `attach<Provider>`,
/// no abstract `AsyncQueryProvider`, no manual lifecycle.
///
/// Both `open` and `inMemory` accept a
/// [MigrationStrategy] for version-tagged,
/// callback-driven schema management. The old
/// `onCreate: (db) => db.migrate()` pattern is still
/// supported for backward compat — when only `onCreate`
/// is provided the runner falls back to the
/// `DbContext.migrations` list.
///
/// ## Example
///
/// ```dart
/// // Open a database (use getDatabasesPath() on mobile
/// // or an absolute path on desktop)
/// final db = await Db.open(path: 'myapp.db');
///
/// // Get a typed set
/// final people = db.set`<Person>`();
///
/// // Query (async, LINQ-style)
/// final adults = await people
///     .asQueryable()
///     .where((p) => p.age >= 18)
///     .toListAsync_();
///
/// // Insert / update
/// await db.set`<Person>`().add(Person(id: 1, name: 'Ada', age: 30));
///
/// // Save changes
/// await db.saveChanges();
///
/// // Close
/// await db.close();
/// ```
library;

import 'package:d_rocket/d_rocket.dart';

/// (SQLite-First): the user-facing database
/// facade. Wraps a [SqliteQueryProvider] (the internal
/// storage engine) and a [DbContext] (the ORM).
///
/// The user never touches either directly. This class
/// exposes the idiomatic operations:
/// `set<T>`, `saveChanges`, `migrate`, `close`.
class Db {
  final SqliteQueryProvider _provider;
  final DbContext _ctx;

  Db._(this._provider, this._ctx);

  /// Opens a file-backed SQLite database at [path]. Use
  /// `getDatabasesPath` from `package:sqflite` on mobile,
  /// or an absolute path on desktop.
  ///
  /// If [password] is non-null, the database is opened as
  /// an encrypted SQLCipher database — see the
  /// `SqliteQueryProvider.file` docstring for the engine
  /// setup. The default (no [password]) is plain SQLite,
  /// preserving the v1.0.x behavior. The parameter is
  /// additive: existing callers that don't pass [password]
  /// are unaffected.
  ///
  /// If [strategy] is provided, the runner
  /// auto-detects the database's current version and
  /// either applies all migrations (`fresh` install),
  /// applies the upgrade subset, or rolls back the
  /// downgrade subset. The `onCreate` callback (if any)
  /// is invoked on a fresh install AFTER the strategy's
  /// declarative `migrations` list (or imperative
  /// `onCreate` callback) has run.
  ///
  /// For backward compat, the pre-strategy
  /// `onCreate: (db) => db.migrate()` pattern is still
  /// supported — when [strategy] is null and [onCreate]
  /// is provided, the runner uses the
  /// `DbContext.migrations` list. Mixing the two
  /// (providing both [strategy] and [onCreate]) is
  /// allowed but the [onCreate] callback runs AFTER the
  /// strategy.
  static Future<Db> open({
    required String path,
    String? password,
    KeyProvider? keyProvider,
    EncryptionConfig? encryptionConfig,
    MigrationStrategy? strategy,
    Future<void> Function(Db db)? onCreate,
  }) async {
    final String? resolvedPassword = await _resolveKey(
      password: password,
      keyProvider: keyProvider,
    );
    final SqliteQueryProvider provider = SqliteQueryProvider.file(
      path,
      password: resolvedPassword,
      encryptionConfig: encryptionConfig,
    );
    final DbContext ctx = _SqliteRocketContext(provider);
    final Db db = Db._(provider, ctx);
    if (strategy != null) {
      await db.migrateStrategy(strategy);
    }
    if (onCreate != null) {
      await onCreate(db);
    }
    return db;
  }

  /// Opens an in-memory database. Convenient for tests.
  /// Same semantics as [open] for [password],
  /// [keyProvider], [encryptionConfig], [strategy] and
  /// [onCreate].
  static Future<Db> inMemory({
    String? password,
    KeyProvider? keyProvider,
    EncryptionConfig? encryptionConfig,
    MigrationStrategy? strategy,
    Future<void> Function(Db db)? onCreate,
  }) async {
    final String? resolvedPassword = await _resolveKey(
      password: password,
      keyProvider: keyProvider,
    );
    final SqliteQueryProvider provider = SqliteQueryProvider.inMemory(
      password: resolvedPassword,
      encryptionConfig: encryptionConfig,
    );
    final DbContext ctx = _SqliteRocketContext(provider);
    final Db db = Db._(provider, ctx);
    if (strategy != null) {
      await db.migrateStrategy(strategy);
    }
    if (onCreate != null) {
      await onCreate(db);
    }
    return db;
  }

  /// helper: validates that exactly one of [password] or
  /// [keyProvider] is set, awaits the key from the
  /// provider (if used), and returns the resolved key.
  /// Throws [ArgumentError] on mutual exclusion or on an
  /// empty key from a [KeyProvider].
  static Future<String?> _resolveKey({
    required String? password,
    required KeyProvider? keyProvider,
  }) async {
    if (password != null && keyProvider != null) {
      throw ArgumentError(
        'Db.open: pass either "password" or "keyProvider", not both',
      );
    }
    if (keyProvider != null) {
      final String resolved = await keyProvider.readKey();
      if (resolved.isEmpty) {
        throw ArgumentError(
          'Db.open: keyProvider returned an empty key',
        );
      }
      return resolved;
    }
    return password;
  }

  /// Returns a typed [DbSet] for entity [T]. Equivalent to
  /// EFCore's `dbContext.Set<T>`.
  ///
  /// The returned `DbSet<T>` has the SQLite provider already
  /// attached — the user doesn't need to call `attach`.
  DbSet<T> set<T>() {
    final DbSet<T> dbSet = _ctx.dbSet<T>(() => _ctx.entityMetaFor<T>());
    // Auto-attach the provider (: hidden from user).
    dbSet.attach<SqliteQueryProvider>(_provider);
    return dbSet;
  }

  /// Returns the underlying [DbContext]. Most users
  /// won't need this — it's exposed for advanced cases
  /// (e.g. running raw SQL via `ctx.database`, or
  /// accessing the change tracker directly).
  DbContext get context => _ctx;

  /// Returns the underlying [SqliteQueryProvider]. Advanced
  /// use only — prefer `set<T>` for typed access.
  SqliteQueryProvider get provider => _provider;

  ///: applies all pending migrations.
  Future<List<MigrationBase>> migrate() => _ctx.migrateAsync();

  ///: rolls back migrations.
  Future<List<MigrationBase>> rollback({List<MigrationBase>? toRollback}) =>
      _ctx.rollbackAsync(toRollback: toRollback);

  ///: brings the database to exactly
  /// [targetVersion] using the `version` of the
  /// provided [MigrationBase] instances. Picks the
  /// direction (upgrade / downgrade) automatically
  /// based on the current schema version. No-op if
  /// already at the target.
  Future<List<MigrationBase>> migrateTo(
    int targetVersion, {
    List<MigrationBase>? migrations,
  }) {
    return _ctx.migrateToAsync(
      targetVersion,
      migrations ?? _ctx.migrations,
    );
  }

  ///: returns the highest version recorded
  /// in `_d_rocket_migrations`, or `0` for a fresh
  /// install. Used by the CLI's `status` command.
  Future<int> currentVersion() => _ctx.currentVersionAsync();

  ///: returns the full list of applied
  /// migrations, ordered by `version` ascending.
  Future<List<AppliedMigration>> appliedMigrations() => _ctx.appliedAsync();

  ///: runs a [MigrationStrategy] against
  /// the open database. The strategy's [MigrationStrategy.version]
  /// is the target. The runner inspects the
  /// current version and dispatches to the right
  /// callback (declarative migrations list /
  /// imperative onCreate / imperative onUpgrade /
  /// imperative onDowngrade).
  Future<List<MigrationBase>> migrateStrategy(MigrationStrategy strategy) {
    return _ctx.migrateStrategyAsync(strategy);
  }

  ///: saves all pending changes in the
  /// change tracker.
  Future<int> saveChanges() => _ctx.saveChangesAsync();

  /// Closes the database. After this, all `set<T>`
  /// operations will throw.
  Future<void> close() => _provider.disposeAsync();
}

/// Internal — a [DbContext] pre-wired to the SQLite
/// provider. Users don't see this class; they interact
/// with [Db] only.
class _SqliteRocketContext extends DbContext {
  _SqliteRocketContext(this._provider);
  final SqliteQueryProvider _provider;

  @override
  AsyncQueryProvider? get asyncProvider => _provider;

  ///: looks up the [EntityMeta] for [T] in
  /// the global [EntityRegistry] populated by
  /// `initializeD` (emitted by `d_rocket_builder`).
  @override
  EntityMeta entityMetaFor<T>() {
    return EntityRegistry.metaFor(T);
  }

  ///: factory for [DbSet]s. The async
  /// provider is auto-attached so the user never has to
  /// call `attachAsyncProvider` themselves.
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    // The DbSet constructor requires sync callbacks
    // (for the back-compat path). The async
    // path is the default — we attach
    // the SQLite provider via `attachAsyncProvider`.
    // The sync callbacks throw because the user is
    // expected to use `*Async` methods.
    return DbSet<T>(
      metaAccessor: m,
      tracker: changeTracker,
      execute: (String sql, List<Object?> binds) {
        throw UnsupportedError(
          'DbSet.execute() is sync-only. Use the `*Async` '
          'methods (e.g. `addAsync`, `selectAsync`) or '
          'await `db.saveChangesAsync()`.',
        );
      },
      select: (String sql, List<Object?> binds) {
        throw UnsupportedError(
          'DbSet.select() is sync-only. Use '
          '`db.set<T>().asQueryable().toListAsync_()`.',
        );
      },
      lastInsertRowId: () {
        throw UnsupportedError(
          'DbSet.lastInsertRowId() is sync-only. Use '
          'the `*Async` methods.',
        );
      },
    ).attachAsyncProvider(_provider).attach<SqliteQueryProvider>(_provider);
  }
}
