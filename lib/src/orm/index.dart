/// Marks a field (or set of fields, in a future)
/// for indexing. The MVP does not emit the
/// `CREATE INDEX` DDL; the annotation is metadata-only
/// and surfaces in the `ColumnMeta` for downstream
/// tooling.
class Index {
  /// Whether the index is unique. Defaults to
  /// `false`.
  final bool unique;

  /// Optional index name. If `null` (the default),
  /// the codegen derives the name as
  /// `<table>_<column>_idx` (or `_unq` for unique
  /// indexes).
  final String? name;

  const Index({this.unique = false, this.name});
}
