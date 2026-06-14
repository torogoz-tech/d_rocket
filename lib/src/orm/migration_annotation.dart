///: marks a top-level function as a
/// code-first migration. The codegen emits a
/// `MigrationBase` subclass (see `migration.dart`)
/// with the given [id] and [name], and an `up` that
/// runs `entityMeta.createTableDdl` for every
/// `@Table` class in the same library.
///
/// Usage:
///
/// ```dart
/// @Migration(id: '001', name: 'Initial schema')
/// MigrationBase initialSchema => _$_InitialSchema;
/// ```
///
/// **Naming note**: this annotation is named
/// `Migration`. The abstract base class that the
/// codegen emits subclasses is named `MigrationBase`
/// (in `migration.dart`). The two names are
/// deliberately distinct so that the same library can
/// have the annotation `@Migration(...)` AND the
/// `MigrationBase` abstract base that the emitted
/// code extends — without a same-library class-name
/// collision.
class Migration {
  /// Stable, lexicographically-ordered identifier.
  final String id;

  /// Human-readable name.
  final String name;

  const Migration({required this.id, required this.name});
}
