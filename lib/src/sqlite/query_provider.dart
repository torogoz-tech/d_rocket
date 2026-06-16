/// The SQLite query provider.
///
/// Owns a `sqlite3.Database` and exposes the operations the
/// queryable needs.
///
///: this class now implements [AsyncQueryProvider]
/// (the async-first storage backend contract). The underlying
/// sqlite3 binding is still synchronous — the `*Async` methods
/// just wrap the sync calls in `Future.value(...)`. The legacy
/// sync methods (`select`, `execute`, `dispose`, `selectWithBinds`)
/// are kept so that existing tests and code can continue to call
/// them without `await` ( will deprecate them in favour
/// of the `*Async` versions).
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:sqlite3/sqlite3.dart';

///: a generic database exception. Wraps any
/// error raised by the underlying sqlite3 binding (and
/// anything thrown by user-defined providers, in the future).
///
/// Use this for `throwsA(isA<DatabaseException>)` matchers
/// in tests, and `try { ... } on DatabaseException catch (e) { ... }`
/// in user code.
///
/// Why a wrapper? The sqlite3 package throws
/// [SqliteException] directly; the refactor moved
/// to `Map<String, Object?>`-based rows and
/// dropped the `package:sqlite3` import from the public
/// barrel. The exception was leaking out as an unhandled
/// type. Wrapping it in [DatabaseException] keeps the
/// public API self-contained.
class DatabaseException implements Exception {
  ///: constructs a [DatabaseException] with
  /// the original cause (if any) and a message.
  DatabaseException(this.message, [this.cause]);

  ///: human-readable description of the
  /// failure (typically the SQL error code and message
  /// from sqlite3, e.g. `"constraint failed: FOREIGN KEY
  /// constraint failed (code 787)"`).
  final String message;

  ///: the original exception, if any. Lets
  /// callers reach the underlying [SqliteException] for
  /// advanced cases (e.g. inspecting `extendedResultCode`).
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'DatabaseException: $message'
      : 'DatabaseException: $message (cause: $cause)';
}

/// helper: wraps a synchronous DB call in a
/// try/catch that converts [SqliteException] (and any other
/// error) into a [DatabaseException]. The original is
/// preserved as the `cause`.
T _wrap<T>(T Function() op) {
  try {
    return op();
  } on DatabaseException {
    rethrow;
  } catch (e) {
    throw DatabaseException(e.toString(), e);
  }
}

/// helper: same as [_wrap] but for `Future<T>`.
Future<T> _wrapAsync<T>(Future<T> Function() op) async {
  try {
    return await op();
  } on DatabaseException {
    rethrow;
  } catch (e) {
    throw DatabaseException(e.toString(), e);
  }
}

/// Owns a `sqlite3.Database` and exposes the operations the
/// queryable needs.
class SqliteQueryProvider implements AsyncQueryProvider {
  final Database _db;

  SqliteQueryProvider._(this._db);

  /// Opens an in-memory database. Convenient for tests and for
  /// ephemeral apps.
  ///
  /// If [password] is non-null, the open call is followed by
  /// `PRAGMA key = '<password>'` and a verification query
  /// (a `SELECT count(*) FROM sqlite_master`) to surface
  /// wrong-password errors as a [DatabaseException] at open
  /// time instead of at first read. The `PRAGMA key` is a
  /// no-op on a vanilla SQLite engine — the consumer is
  /// responsible for bundling a SQLCipher build
  /// (`sqlcipher_flutter_libs` on Flutter, or `libsqlcipher`
  /// installed system-wide on desktop) when [password] is
  /// non-null. See `doc/13-faq.md` for the full setup.
  factory SqliteQueryProvider.inMemory({String? password}) {
    final Database db = sqlite3.openInMemory();
    if (password != null) {
      _applyPragmaKey(db, password);
    }
    return SqliteQueryProvider._(db);
  }

  /// Opens a file-backed database at [path].
  ///
  /// If [password] is non-null, the open call is followed by
  /// `PRAGMA key = '<password>'` and a verification query
  /// (a `SELECT count(*) FROM sqlite_master`) to surface
  /// wrong-password errors as a [DatabaseException] at open
  /// time instead of at first read. The `PRAGMA key` is a
  /// no-op on a vanilla SQLite engine — the consumer is
  /// responsible for bundling a SQLCipher build
  /// (`sqlcipher_flutter_libs` on Flutter, or `libsqlcipher`
  /// installed system-wide on desktop) when [password] is
  /// non-null. See `doc/13-faq.md` for the full setup.
  factory SqliteQueryProvider.file(String path, {String? password}) {
    final Database db = sqlite3.open(path);
    if (password != null) {
      _applyPragmaKey(db, password);
    }
    return SqliteQueryProvider._(db);
  }

  /// Wraps an existing `Database` instance. Use this if the caller
  /// has already opened the database (e.g. via `sqlite3.openInMemory`)
  /// and wants to keep ownership of the lifecycle.
  factory SqliteQueryProvider.fromDatabase(Database db) =>
      SqliteQueryProvider._(db);

  /// helper: runs `PRAGMA key = '<escaped>'` and verifies the
  /// key works. Throws [DatabaseException] on wrong password
  /// (the underlying engine raises `SQLITE_NOTADB` on the
  /// first read of an encrypted page when the key is wrong).
  /// Single quotes in [password] are escaped by doubling
  /// (`O'Brien` -> `O''Brien`), so user input is safe to
  /// interpolate.
  static void _applyPragmaKey(Database db, String password) {
    final String escaped = password.replaceAll("'", "''");
    db.execute("PRAGMA key = '$escaped'");
    try {
      db.select('SELECT count(*) FROM sqlite_master');
    } on SqliteException catch (e) {
      db.close();
      throw DatabaseException(
        'Failed to open encrypted database: the password is '
        'incorrect, the file is not a SQLCipher database, or '
        'the underlying engine is not SQLCipher. '
        'See doc/13-faq.md for the SQLCipher setup. '
        'Underlying error: ${e.toString()}',
        e,
      );
    }
  }

  /// The underlying `Database`. Exposed for callers that need to
  /// run ad-hoc SQL.
  Database get database => _db;

  // ─── Legacy sync API (kept for backward compatibility) ─────

  /// Legacy sync API (pre-). Use [selectAsync] in
  /// new code.
  List<Row> select(String sql) => _wrap(() => _db.select(sql));

  /// Legacy sync API (pre-). Use [selectAsync] in
  /// new code.
  List<Row> selectWithBinds(String sql, List<Object?> binds) {
    return _wrap(() {
      if (binds.isEmpty) return _db.select(sql);
      final stmt = _db.prepare(sql);
      try {
        return stmt.select(binds);
      } finally {
        stmt.close();
      }
    });
  }

  /// Legacy sync API (pre-). Use [executeAsync] in
  /// new code.
  void execute(String sql, [List<Object?>? binds]) {
    _wrap(() {
      if (binds == null || binds.isEmpty) {
        _db.execute(sql);
        return;
      }
      final stmt = _db.prepare(sql);
      try {
        stmt.execute(binds);
      } finally {
        stmt.close();
      }
    });
  }

  /// Legacy sync API (pre-). Use [disposeAsync] in
  /// new code.
  void dispose() => _db.close();

  // ─── async API (implements [AsyncQueryProvider]) ──

  @override
  Future<List<Object?>> selectAsync(String sql, [List<Object?>? binds]) {
    return _wrapAsync(() async {
      if (binds == null || binds.isEmpty) {
        return select(sql);
      }
      return selectWithBinds(sql, binds);
    });
  }

  @override
  Future<void> executeAsync(String sql, [List<Object?>? binds]) {
    return _wrapAsync(() async {
      execute(sql, binds);
    });
  }

  @override
  Future<int> lastInsertRowIdAsync() async => _wrap(() => _db.lastInsertRowId);

  @override
  Future<void> beginTransactionAsync() async {
    execute('BEGIN');
  }

  @override
  Future<void> commitAsync() async {
    execute('COMMIT');
  }

  @override
  Future<void> rollbackAsync() async {
    execute('ROLLBACK');
  }

  @override
  Future<void> disposeAsync() async {
    _db.close();
  }
}
