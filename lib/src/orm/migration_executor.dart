/// Callback signature for executing a single SQL
/// statement (optionally with positional binds).
///
/// Mirrors the execute callback that `DbSet` takes,
/// so the user can pass the same provider hook used
/// by `DbContext` to the migration runner.
typedef MigrationExecutor = void Function(
  String sql, [
  List<Object?>? binds,
]);
