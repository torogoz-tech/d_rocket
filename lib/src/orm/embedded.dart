///: marks a field as an embedded
/// value object (EF Core's `OwnsOne` /
/// `ComplexProperty` pattern). The fields of the
/// embedded type are flattened into the parent
/// table — they don't get their own table and they
/// don't carry an FK.
class Embedded {
  /// Optional prefix to apply to the embedded column
  /// names. If `null` (the default), the columns are
  /// emitted as-is (e.g. `street`, `city`). If non-null
  /// (e.g. `'addr'`), the columns are emitted as
  /// `addr_street`, `addr_city`.
  final String? prefix;

  const Embedded({this.prefix});
}
