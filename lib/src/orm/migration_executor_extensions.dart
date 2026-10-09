import 'migration_executor.dart';

/// Convenience SQL operations for hand-written migrations.
extension MigrationExecutorExtensions on MigrationExecutor {
  /// Adds a column using the supplied SQLite column definition.
  void addColumn(String table, String column, String definition) {
    this('ALTER TABLE ${quoteIdentifier(table)} '
        'ADD COLUMN ${quoteIdentifier(column)} $definition');
  }

  /// Renames a table.
  void renameTable(String table, String newName) {
    this('ALTER TABLE ${quoteIdentifier(table)} '
        'RENAME TO ${quoteIdentifier(newName)}');
  }

  /// Renames a column using SQLite's native ALTER TABLE operation.
  void renameColumn(String table, String column, String newName) {
    this('ALTER TABLE ${quoteIdentifier(table)} '
        'RENAME COLUMN ${quoteIdentifier(column)} '
        'TO ${quoteIdentifier(newName)}');
  }

  /// Drops a table only when it exists.
  void dropTableIfExists(String table) {
    this('DROP TABLE IF EXISTS ${quoteIdentifier(table)}');
  }

  /// Drops an index only when it exists.
  void dropIndexIfExists(String index) {
    this('DROP INDEX IF EXISTS ${quoteIdentifier(index)}');
  }

  /// Creates an index from a complete column expression.
  void createIndex(
    String index,
    String table,
    String columns, {
    bool unique = false,
  }) {
    this('CREATE ${unique ? 'UNIQUE ' : ''}INDEX ${quoteIdentifier(index)} '
        'ON ${quoteIdentifier(table)} ($columns)');
  }

  /// Rebuilds a table for operations SQLite cannot express with ALTER TABLE.
  ///
  /// [createTableSql] must create [table] with its final schema. Only the
  /// explicitly listed [columns] are copied, so a migration can intentionally
  /// transform or omit columns. The runner executes these statements inside
  /// its migration transaction.
  void rebuildTable(
    String table,
    String createTableSql, {
    required List<String> columns,
    String? temporaryTable,
  }) {
    if (columns.isEmpty) {
      throw ArgumentError.value(
        columns,
        'columns',
        'At least one column is required.',
      );
    }
    final String temp = temporaryTable ?? '${table}__d_rocket_old';
    final String columnList = columns.map(quoteIdentifier).join(', ');
    this('ALTER TABLE ${quoteIdentifier(table)} '
        'RENAME TO ${quoteIdentifier(temp)}');
    this(createTableSql);
    this('INSERT INTO ${quoteIdentifier(table)} ($columnList) '
        'SELECT $columnList FROM ${quoteIdentifier(temp)}');
    this('DROP TABLE ${quoteIdentifier(temp)}');
  }
}

/// Quotes a SQLite identifier and rejects embedded quote characters.
String quoteIdentifier(String value) {
  if (value.isEmpty || value.contains('"')) {
    throw ArgumentError.value(value, 'value', 'Invalid SQLite identifier.');
  }
  return '"$value"';
}
