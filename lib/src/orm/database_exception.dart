/// Generic database exception. Engine-agnostic.
///
/// Wraps an engine-specific exception (e.g. the
/// SQLite `SqliteException`, the Postgres
/// `PgException`) into a uniform type that the
/// rest of d_rocket can catch without knowing
/// which engine produced it.
///
/// The [cause] is the original exception, kept
/// for debugging. The [message] is the user-
/// facing description.
///
/// In Phase 1, this class lives in
/// `lib/src/orm/database_exception.dart` so that
/// it does not depend on `package:sqlite3` (and
/// can be exported from the d_rocket barrel
/// without dragging the sqlite3 types into
/// consumer code that does not use the ORM).
library;

class DatabaseException implements Exception {
  DatabaseException(this.message, {this.cause, this.sql, this.code});

  /// User-facing description. Should be safe to
  /// surface in logs and to the user.
  final String message;

  /// The original engine exception, if any. Kept
  /// for debugging; the dev can call `.toString()`
  /// on it to see the engine-specific details.
  final Object? cause;

  /// The SQL statement that produced the error,
  /// if known. May be null for non-statement
  /// errors (e.g. open failures).
  final String? sql;

  /// The engine-specific error code (e.g. the
  /// SQLite extended error code). May be null.
  final Object? code;

  @override
  String toString() {
    final buf = StringBuffer('DatabaseException: $message');
    if (sql != null) {
      buf.write('\n  sql: $sql');
    }
    if (code != null) {
      buf.write('\n  code: $code');
    }
    if (cause != null) {
      buf.write('\n  cause: $cause');
    }
    return buf.toString();
  }
}
