/// Callback signature for a `SELECT` statement.
/// Returns a list of rows, where each row is a
/// `Map<String, Object?>` keyed by the column names.
/// Mirrors the `DbSet.select` contract.
typedef MigrationSelector = List<Map<String, Object?>> Function(
  String sql, [
  List<Object?>? binds,
]);
