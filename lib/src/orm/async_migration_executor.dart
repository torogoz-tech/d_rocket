/// Callback signature for executing a single SQL
/// statement asynchronously. Mirrors
/// `AsyncQueryProvider.executeAsync`.
typedef AsyncMigrationExecutor = Future<void> Function(
  String sql, [
  List<Object?>? binds,
]);
