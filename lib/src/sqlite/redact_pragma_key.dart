/// Redacts the value of a `PRAGMA key = '...'` or
/// `PRAGMA rekey = '...'` statement, replacing the
/// literal with `'***'`.
///
/// Useful for application-level logging of SQL
/// traces when the database is encrypted and the
/// password must not appear in logs, crash reports,
/// or any other observer. The function is
/// case-insensitive and tolerant of whitespace
/// variations; it only matches the single-quoted
/// form (which is what d_rocket itself emits when
/// applying the key).
///
/// ## Example
///
/// ```dart
/// redactPragmaKey("PRAGMA key = 'hunter2'");
/// // -> "PRAGMA key = '***'"
///
/// redactPragmaKey("PRAGMA rekey = 'O''Brien'");
/// // -> "PRAGMA rekey = '***'"
///
/// redactPragmaKey("SELECT * FROM users");
/// // -> "SELECT * FROM users"  (unmodified)
/// ```
///
/// The function does NOT try to detect keys that
/// are passed via a `?` placeholder — `PRAGMA` does
/// not accept bound parameters in SQLite, so a
/// `PRAGMA key = ?` form is a no-op in the engine
/// and has no key value to redact.
String redactPragmaKey(String sql) {
  return sql.replaceAllMapped(
    RegExp(
      r"""(PRAGMA\s+(?:key|rekey)\s*=\s*)'((?:[^']|'')*)'""",
      caseSensitive: false,
    ),
    (Match m) => "${m.group(1)}'***'",
  );
}
