import 'on_delete_action.dart';

/// Metadata for a single column of a `@Table`
/// entity. Emitted by the codegen as part of the
/// `EntityMeta` literal; the runtime never
/// constructs a `ColumnMeta` by itself.
class ColumnMeta {
  /// SQL column name (already snake_case'd by the codegen).
  final String sqlName;

  /// Dart field name on the user class.
  final String dartField;

  /// Dart runtime type of the field (`int`, `String`,
  /// …). Used to choose the right bind coercion in
  /// `SaveChanges`.
  final Type dartType;

  /// Whether the column allows `NULL` in the database.
  final bool nullable;

  /// Optional DDL default (stored as a literal `String`
  /// so it can be embedded directly into the `CREATE
  /// TABLE` statement; `null` means "no default").
  final String? defaultLiteral;

  /// Whether this column is the primary key.
  final bool isPrimaryKey;

  /// Whether the primary key is `AUTOINCREMENT`.
  final bool isAutoIncrement;

  /// Whether this column is a foreign key. Set by the
  /// codegen when the field is annotated with
  /// `@ForeignKey(...)` or `@Column(isForeignKey:
  /// true)`.
  final bool isForeignKey;

  /// Foreign-key target table. `null` for non-FK
  /// columns.
  final String? foreignTable;

  /// Foreign-key target column. `null` for non-FK
  /// columns.
  final String? foreignColumn;

  /// Whether this column is indexed. Set by the
  /// codegen when the field is annotated with
  /// `@Index`.
  final bool isIndexed;

  /// Whether the index is unique.
  final bool isUniqueIndex;

  /// Override for the SQL index name. `null` means
  /// "let the runtime derive it as
  /// `<table>_<column>_idx` (or `_unq` for unique
  /// indexes)".
  final String? indexName;

  /// The `ON DELETE` action for this foreign key.
  /// Default is [OnDeleteAction.noAction].
  final OnDeleteAction onDelete;

  const ColumnMeta({
    required this.sqlName,
    required this.dartField,
    required this.dartType,
    this.nullable = false,
    this.defaultLiteral,
    this.isPrimaryKey = false,
    this.isAutoIncrement = false,
    this.isForeignKey = false,
    this.foreignTable,
    this.foreignColumn,
    this.isIndexed = false,
    this.isUniqueIndex = false,
    this.indexName,
    this.onDelete = OnDeleteAction.noAction,
  });
}

/// Emit the `REFERENCES … [ON DELETE …]` SQL fragment
/// for a [ColumnMeta] that is a foreign key. Returns
/// the empty string for non-FK columns.
String fkClause(ColumnMeta c) {
  if (!c.isForeignKey) return '';
  final base = 'REFERENCES "${c.foreignTable}"("${c.foreignColumn}")';
  switch (c.onDelete) {
    case OnDeleteAction.cascade:
      return '$base ON DELETE CASCADE';
    case OnDeleteAction.setNull:
      return '$base ON DELETE SET NULL';
    case OnDeleteAction.restrict:
      return '$base ON DELETE RESTRICT';
    case OnDeleteAction.noAction:
      return base;
  }
}
