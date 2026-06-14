/// Marks a field as a column of its `@Table`
/// entity.
///
/// Fields that are not annotated as `@PrimaryKey` or
/// `@Column` are ignored by the ORM. (This keeps
/// the model free to have computed fields, transient
/// state, or methods without polluting the table
/// DDL.)
class Column {
  /// SQL column name. If `null` (the default), the
  /// codegen derives the column name from the field
  /// name (snake_case).
  final String? name;

  /// Whether the column accepts `NULL`. Defaults to
  /// `false` (NOT NULL). The DDL emitted by the
  /// codegen respects this.
  final bool nullable;

  /// Optional default value for the column. The
  /// codegen embeds the literal into the
  /// `CREATE TABLE` statement.
  final Object? defaultValue;

  /// Whether this column is a foreign key. Defaults
  /// to `false`. The codegen surfaces this as part
  /// of the generated `ColumnMeta`.
  final bool isForeignKey;

  ///: marks this column as the TPH
  /// discriminator. Exactly one column per TPH root
  /// should set this to `true`.
  final bool discriminator;

  const Column({
    this.name,
    this.nullable = false,
    this.isForeignKey = false,
    this.defaultValue,
    this.discriminator = false,
  });
}
