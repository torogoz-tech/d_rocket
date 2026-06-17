/// The abstract engine interface for db-agnostic
/// database access.
///
/// An engine owns:
/// - The native binding (libsqlite3, libpq, libsql
///   WASM, etc.).
/// - The connection lifecycle (open, close, transactions).
/// - The translation of d_rocket's [AsyncQueryProvider]
///   semantics into the engine's native API.
///
/// Every engine ships as a separate pub.dev package
/// (`d_rocket_engine_sqlite`, `d_rocket_engine_postgres`,
/// `d_rocket_engine_libsql_wasm`) and registers
/// itself at app startup via
/// `EngineRegistry.register(...)`.
///
/// The engine's [open] method returns an
/// [AsyncQueryProvider] — the engine-agnostic
/// query interface that the rest of d_rocket
/// (DbContext, DbSet, the LINQ → SQL translator,
/// the auto-migrator) talks to. This way, the
/// 4 layers of d_rocket are identical across
/// engines; only the engine implementation
/// differs.
library;

import 'async_query_provider.dart';
import '../sqlite/encryption_config.dart';

abstract class DbEngine {
  /// A short identifier for the engine, e.g.
  /// "sqlite", "postgres", "libsql-wasm". Used
  /// in error messages and in the `__engine`
  /// column of the schema_state table.
  String get name;

  /// Whether the engine's native library is
  /// available on the current platform. The dev
  /// can call this before `Db.open` to get a
  /// friendlier error than a late-stage
  /// `StateError` from a missing `dart:ffi`
  /// symbol.
  bool get isAvailable;

  /// Open a database connection.
  ///
  /// The [path] is the engine-specific location:
  /// a file path for SQLite, a connection string
  /// for Postgres, etc. Optional.
  ///
  /// The [password] enables encryption. The
  /// [encryptionConfig] is engine-specific
  /// tunables (kdf iterations, hmac size, page
  /// size, etc.). For engines that do not
  /// support encryption, the parameters are
  /// ignored.
  Future<AsyncQueryProvider> open({
    String? path,
    String? password,
    EncryptionConfig? encryptionConfig,
  });
}
