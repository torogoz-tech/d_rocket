/// The legacy sync query provider contract.
///
/// In d_rocket 1.x, the SQLite engine exposed
/// a synchronous query API: `selectWithBinds`
/// returned `List<Row>` directly (no `Future`).
/// This API was tied to the synchronous
/// `package:sqlite3` binding, which has no
/// equivalent in the Postgres engine
/// (`package:postgres` is async-only) and
/// no equivalent in the future libsql_wasm
/// engine (WASM is async-only).
///
/// In d_rocket 2.0.0, the canonical LINQ API
/// is async (`toListAsync_`, `countAsync_`,
/// etc.) and is engine-agnostic. The legacy
/// sync API (`toList_`, `count_`, `first_`,
/// `sum_`, `min_`, `max_`) is **engine-
/// specific**: only engines that have a
/// synchronous query path expose it.
///
/// An engine exposes the legacy sync API by
/// implementing [LegacySyncQueryProvider].
/// The [Queryable] (in d_rocket core) checks
/// at runtime: if the provider is a
/// [LegacySyncQueryProvider], the sync
/// methods work; otherwise they throw a
/// clear "this engine is async-only; use the
/// `*Async_` methods" error.
///
/// ## Implementations
///
/// * `d_rocket_engine_sqlite`:
///   `SqliteQueryProvider implements LegacySyncQueryProvider`
///   (the `package:sqlite3` binding is sync,
///   so the legacy API is available).
/// * `d_rocket_engine_postgres`:
///   `PostgresQueryProvider` does NOT
///   implement this. The legacy sync methods
///   throw at runtime; the user must use
///   `toListAsync_` etc.
/// * `d_rocket_engine_libsql_wasm` (2.1):
///   the WASM binding is async-only, so the
///   `WasmQueryProvider` will NOT implement
///   this either.
///
/// ## Migration
///
/// The legacy sync API is scheduled for
/// removal in 3.0.0. New code should use
/// `toListAsync_` etc. The legacy methods
/// are kept in 2.0.0 for back-compat with
/// 1.x code that hasn't been migrated yet.
library;

/// The legacy sync query provider contract.
///
/// An engine implements this to expose the
/// 1.x-style sync LINQ API (`toList_`,
/// `count_`, etc.). The interface has a
/// single method: [selectWithBinds], which
/// returns the rows synchronously.
///
/// The row type is `Map<String, Object?>`
/// (the standard `Row` shape used by all
/// engines; SQLite's `Row` is itself a
/// `Map<String, Object?>`).
abstract class LegacySyncQueryProvider {
  /// Runs a `SELECT` synchronously and
  /// returns the raw rows. No `Future`
  /// wrapping — the call is synchronous
  /// (the underlying binding is sync).
  ///
  /// The [binds] list contains one entry
  /// per `?` in the SQL.
  List<Map<String, Object?>> selectWithBinds(
    String sql,
    List<Object?> binds,
  );
}
