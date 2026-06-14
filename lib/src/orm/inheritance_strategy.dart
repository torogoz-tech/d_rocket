/// The inheritance strategy used by a hierarchy of
/// entities. Mirrors EF Core's `InheritanceStrategy`
/// enum, which has the same three values
/// (`Tph`, `Tpt`, `Tpc`). d_rocket supports all three.
enum InheritanceStrategy {
  /// None (the default): the entity has no parent
  /// class. The DDL is emitted as a single table with
  /// the entity's columns.
  none,

  /// TPH (Table-Per-Hierarchy): the entity is either
  /// the root of a TPH hierarchy (a single table
  /// holds the root + every child, with a discriminator
  /// column telling them apart) or a child of such
  /// a hierarchy.
  tph,

  /// TPT (Table-Per-Type): the entity is the root of a
  /// TPT hierarchy (the root owns its own table) or a
  /// child (the child owns its own table with its
  /// specific columns + a FK to the root's PK; a JOIN
  /// materialises the full row).
  tpt,

  /// TPC (Table-Per-Concrete-Class): the entity is
  /// the root of a TPC hierarchy (the root has
  /// no table — conceptual type) or a leaf (the
  /// leaf owns its own table with all the columns
  /// — root's + leaf's — duplicated). No JOINs needed.
  tpc,
}
