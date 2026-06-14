/// Callback signature for a `SELECT` statement,
/// asynchronously. Mirrors
/// `AsyncQueryProvider.selectAsync`.
typedef AsyncMigrationSelector = Future<List<Map<String, Object?>>> Function(
  String sql, [
  List<Object?>? binds,
]);
