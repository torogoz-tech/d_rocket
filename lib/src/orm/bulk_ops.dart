//: bulk operations —
// `executeUpdateAsync` / `executeDeleteAsync`.
//
// Mirrors EF Core 7+'s
// `dbContext.Orders.Where(...).ExecuteUpdateAsync(...)` /
// `ExecuteDeleteAsync(...)`. The pattern: compile a
// single SQL statement that updates / deletes
// every row matching a predicate — no entity
// materialisation, no change tracker, no
// round-trips per row. On mobile, where I/O is
// expensive and battery is precious, this is the
// difference between a snappy app and a slow one.
//
// In d_rocket, the user calls these directly on
// the [AsyncQueryProvider] (the lowest layer) and
// passes the table name, the SET map (for UPDATE),
// and an optional WHERE clause. The LINQ wrapper
// will compile the LINQ tree to these
// calls.

import 'async_query_provider.dart';

/// (bulk update): extension on
/// [AsyncQueryProvider] that runs a single
/// `UPDATE <table> SET col1 = ?, col2 = ? [WHERE ...]`
/// statement.
///
/// Returns the number of affected rows.
///
/// Example:
///
/// ```dart
/// // Mark every book with stock < 10 as low_stock = true.
/// final int affected = await provider.executeUpdateAsync(
/// table: 'books',
/// setters: <String, Object?>{'low_stock': true},
/// where: 'stock < ?',
/// whereBinds: <Object?>[10],
///);
/// ```
///
/// Before (slow, 3 round-trips per row):
///
/// ```dart
/// final List`<Book>` books = await provider.selectAsync(
/// 'SELECT * FROM books WHERE stock < ?',
/// <Object?>[10],
///);
/// for (final Book b in books) {
/// await provider.executeAsync(
/// 'UPDATE books SET low_stock = ? WHERE id = ?',
/// <Object?>[true, b.id],
///);
/// }
/// ```
///
/// After (1 round-trip total):
///
/// ```dart
/// await provider.executeUpdateAsync(
/// table: 'books',
/// setters: <String, Object?>{'low_stock': true},
/// where: 'stock < ?',
/// whereBinds: <Object?>[10],
///);
/// ```
extension BulkOpsAsync on AsyncQueryProvider {
  ///: runs a single
  /// `UPDATE <table> SET col1 = ?, col2 = ? [WHERE ...]`.
  ///
  /// [table] is the table name.
  /// [setters] is the `column → value` map. Each
  /// value is bound as a positional `?` parameter
  /// (so user input is safe from SQL injection).
  /// [where] is an optional `WHERE` clause (without
  /// the `WHERE` keyword); pass `null` to update
  /// every row.
  /// [whereBinds] are the positional binds for
  /// [where] (in order).
  ///
  /// Returns the number of affected rows.
  Future<int> executeUpdateAsync({
    required String table,
    required Map<String, Object?> setters,
    String? where,
    List<Object?>? whereBinds,
  }) async {
    if (setters.isEmpty) {
      throw ArgumentError(
        'executeUpdateAsync: setters map must be non-empty',
      );
    }
    // (SQL builder): build the
    // `UPDATE <table> SET col1 = ?, col2 = ?` SQL.
    final String setClause =
        setters.keys.map((String col) => '$col = ?').join(', ');
    final StringBuffer sql = StringBuffer()
      ..write('UPDATE $table SET $setClause');
    final List<Object?> binds = <Object?>[...setters.values];
    if (where != null && where.isNotEmpty) {
      sql.write(' WHERE $where');
      if (whereBinds != null) binds.addAll(whereBinds);
    }
    // sqflite's `rawInsert` returns the new row id
    // for INSERT statements. For UPDATE, the
    // underlying engine (sqlite3 / sqflite / postgres)
    // returns the number of affected rows via a
    // different path. We use a query that reports
    // `changes` (SQLite) or `ROW_COUNT` (Postgres)
    // as a follow-up to extract the count.
    await executeAsync(sql.toString(), binds);
    // (affected count): read the
    // affected row count via SQLite's `changes`
    // function. This is a SQLite-specific
    // implementation detail; Postgres would use
    // `ROW_COUNT` (or rely on a different
    // provider path).
    final List<Object?> rows = await selectAsync(
      'SELECT changes() AS c',
    );
    if (rows.isEmpty) return 0;
    final Object? c = (rows.first as Map<String, Object?>)['c'];
    return c is int ? c : 0;
  }

  /// (bulk delete): runs a single
  /// `DELETE FROM <table> [WHERE ...]` statement.
  ///
  /// Returns the number of affected rows.
  ///
  /// Example:
  ///
  /// ```dart
  /// // Delete every cancelled order older than a year.
  /// final int affected = await provider.executeDeleteAsync(
  /// table: 'orders',
  /// where: 'status = ? AND created_at < ?',
  /// whereBinds: <Object?>['cancelled', oneYearAgo],
  ///);
  /// ```
  Future<int> executeDeleteAsync({
    required String table,
    String? where,
    List<Object?>? whereBinds,
  }) async {
    final StringBuffer sql = StringBuffer()..write('DELETE FROM $table');
    if (where != null && where.isNotEmpty) {
      sql.write(' WHERE $where');
    }
    await executeAsync(sql.toString(), whereBinds);
    final List<Object?> rows = await selectAsync(
      'SELECT changes() AS c',
    );
    if (rows.isEmpty) return 0;
    final Object? c = (rows.first as Map<String, Object?>)['c'];
    return c is int ? c : 0;
  }
}
