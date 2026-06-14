import 'inheritance_strategy.dart';

/// Marks a class as an entity managed by the d_rocket
/// ORM.
///
/// The codegen produces a `static EntityMeta entityMeta`
/// for every annotated class and a `register<X>EntityMeta`
/// that populates the global `EntityRegistry` from the
/// central `initializeD`.
///
/// Example:
/// ```dart
/// @Table
/// class Author extends Record {
/// Author({required this.id, required this.name});
///
/// @PrimaryKey
/// final int id;
///
/// @Column(nullable: false)
/// final String name;
/// }
/// ```
class Table {
  /// SQL table name. If `null` (the default), the
  /// codegen derives the table name from the class
  /// name (snake_case).
  final String? name;

  ///: the inheritance role of this
  /// class. Set to `'root'` for the root of a TPH
  /// hierarchy, or to a discriminator value (e.g.
  /// `'dog'`) for a child entity.
  final String? discriminator;

  ///: the TPH children of this entity
  /// (only meaningful when [inheritance] ==
  /// [InheritanceStrategy.tph]). Map keys are the
  /// discriminator values (e.g. `'dog'`, `'cat'`)
  /// and the values are the Dart class names of
  /// the child entities.
  final Map<String, String>? children;

  ///: marks this entity as a TPC
  /// root that owns no table. The leaf entities
  /// own the actual tables.
  final bool isAbstract;

  /// The inheritance strategy of this entity. Defaults
  /// to [InheritanceStrategy.none].
  final InheritanceStrategy inheritance;

  const Table({
    this.name,
    this.discriminator,
    this.inheritance = InheritanceStrategy.none,
    this.children,
    this.isAbstract = false,
  });

  ///: convenience constructor for TPH
  /// roots.
  const Table.tph({
    String? name,
    Map<String, String>? children,
  }) : this(
          name: name,
          inheritance: InheritanceStrategy.tph,
          children: children,
        );

  ///: convenience constructor for
  /// TPC roots.
  const Table.tpc({
    String? name,
  }) : this(
          name: name,
          inheritance: InheritanceStrategy.tpc,
          isAbstract: true,
        );
}
