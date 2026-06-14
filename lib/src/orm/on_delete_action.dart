/// `ON DELETE` policy for foreign-key columns. Maps
/// directly to SQLite's `ON DELETE CASCADE / SET NULL
/// / RESTRICT / NO ACTION` clauses (and to EF Core's
/// `OnDelete` enum, for parity).
enum OnDeleteAction {
  /// Cascade: when the parent row is deleted, the
  /// dependent rows are also deleted (recursively).
  cascade,

  /// Set null: when the parent row is deleted, the FK
  /// column on the dependent rows is set to `NULL`.
  /// The column MUST be nullable.
  setNull,

  /// Restrict: the DB rejects the `DELETE` of the
  /// parent row if any dependent row references it.
  restrict,

  /// No action (the default): no `ON DELETE`
  /// clause is emitted. The DB uses its own default
  /// (which is `NO ACTION` in SQLite).
  noAction,
}
