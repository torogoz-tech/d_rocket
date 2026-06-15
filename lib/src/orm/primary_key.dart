/// Marks a field as the primary key of its
/// `@Table`.
///
/// Exactly one field per entity class must carry
/// this annotation.
///
/// The column's SQL type is derived from the
/// field's Dart type:
///   * `int`  -> `INTEGER PRIMARY KEY [AUTOINCREMENT]`
///   * `String` -> `TEXT PRIMARY KEY` (use for
///     client-generated UUIDs; pass `autoIncrement:
///     false`)
///   * `DateTime` -> `TEXT PRIMARY KEY`
///
/// The `autoIncrement` flag only applies to
/// `int` PKs (SQLite's `AUTOINCREMENT` is
/// restricted to `INTEGER PRIMARY KEY`). On a
/// non-`int` PK the value of `autoIncrement`
/// is ignored at DDL-generation time.
class PrimaryKey {
  /// Whether the PK should auto-increment. Only
  /// meaningful for `int` PKs; the codegen
  /// rejects this flag on non-`int` fields.
  /// Defaults to `true` because the most common
  /// case is an auto-incrementing `int` row id.
  final bool autoIncrement;

  const PrimaryKey({this.autoIncrement = true});
}
