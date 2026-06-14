import 'column.dart';

/// Marks a field as a foreign key referencing
/// another `@Table`.
///
/// Convenience wrapper around [Column] with
/// `isForeignKey: true` and a target table/column
/// reference. The codegen surfaces the reference in
/// the `ColumnMeta` and the `EntityMeta` but does not
/// emit `FOREIGN KEY … REFERENCES …` in the DDL (yet).
class ForeignKey extends Column {
  /// The target table (e.g. `'authors'`). Must be
  /// the snake_case table name, not the Dart class
  /// name.
  final String table;

  /// The target column in the referenced table
  /// (e.g. `'id'`).
  final String column;

  const ForeignKey({
    super.name,
    super.nullable,
    super.defaultValue,
    required this.table,
    required this.column,
  }) : super(isForeignKey: true);
}
