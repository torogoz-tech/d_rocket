///: the async-first query provider contract.
///
/// Every d_rocket storage backend (SQLite, Postgres, MySQL,
/// in-memory, …) implements this interface. The interface is
/// the single source of truth for "how the ORM talks to a
/// database" — every `DbSet` read / write goes through one of
/// these methods.
///
/// Method naming convention: the async methods have an
/// `Async` suffix (e.g. `executeAsync`, `selectAsync`). This
/// is a transitional convention — the long-term plan (
/// 5.x) is to drop the suffix once the entire ORM core
/// (`DbSet`, `DbContext`, `Queryable`, `MigrationBase`)
/// has been migrated to async and the legacy sync API on
/// the providers is removed.
abstract class AsyncQueryProvider {
  /// Executes a statement that returns no rows (e.g.
  /// `CREATE TABLE`, `INSERT`, `UPDATE`, `DELETE`).
  ///
  /// The [binds] list contains one entry per `?` in the
  /// SQL. `null` or empty means "no bind parameters".
  Future<void> executeAsync(String sql, [List<Object?>? binds]);

  /// Executes a `SELECT` and returns the raw rows. The
  /// runtime does not interpret the row format; the
  /// `EntityMeta.fromRow` (provided by codegen) does.
  ///
  /// MVP note: the row shape is `List<Object?>` of
  /// `Map<String, Object?>` entries (one per row). SQLite's
  /// `Row` is itself a `Map<String, dynamic>`, so it
  /// satisfies the contract via Dart's covariance. Postgres
  /// drivers return a similar shape.
  Future<List<Object?>> selectAsync(String sql, [List<Object?>? binds]);

  /// Returns the `ROWID` of the last successful `INSERT`.
  /// Only meaningful for SQLite (per-connection property)
  /// and Postgres (via the `RETURNING` clause or
  /// `lastval`). Throws if the provider doesn't support
  /// it.
  Future<int> lastInsertRowIdAsync();

  /// Begins a transaction. The caller is responsible for
  /// calling [commitAsync] or [rollbackAsync] exactly once.
  ///
  /// Nesting (a transaction inside a transaction) is not
  /// supported in the MVP — the provider should throw on
  /// nested `begin`.
  Future<void> beginTransactionAsync();

  /// Commits the current transaction. No-op if there is
  /// no active transaction.
  Future<void> commitAsync();

  /// Rolls back the current transaction. No-op if there is
  /// no active transaction.
  Future<void> rollbackAsync();

  /// Closes the provider and releases its resources. After
  /// `disposeAsync`, the provider is unusable.
  Future<void> disposeAsync();
}
