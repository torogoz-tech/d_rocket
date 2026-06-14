/// Marks a field as the primary key of its
/// `@Table`.
///
/// Exactly one field per entity class must carry
/// this annotation. The codegen uses the
/// `autoIncrement` flag to decide whether to emit
/// `INTEGER PRIMARY KEY AUTOINCREMENT` (default) or
/// just `INTEGER PRIMARY KEY` for the column DDL.
class PrimaryKey {
  /// Whether the underlying `INTEGER PRIMARY KEY`
  /// should auto-increment. Defaults to `true`
  /// because that is the most common case.
  final bool autoIncrement;

  const PrimaryKey({this.autoIncrement = true});
}
