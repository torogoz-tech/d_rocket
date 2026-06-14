///: a single row in the `_d_rocket_migrations`
/// tracking table. Returned by
/// [MigrationRunner.applied] / [MigrationRunner.appliedAsync],
/// and used by the CLI's `status` subcommand.
library;

///: a row from the `_d_rocket_migrations`
/// table. Materialized into a typed struct so the user
/// doesn't have to parse `Map<String, Object?>` rows by
/// hand.
class AppliedMigration {
  /// The string id of the migration (primary key in
  /// the tracking table). For the conventional style
  /// scaffolded by `migration add` this is a
  /// 0-padded numeric string (`'001'`, `'002'`, …).
  final String id;

  /// Human-readable name. Free-form, set by the
  /// author of the migration.
  final String name;

  ///: the integer version of the migration.
  /// `null` for pre—10 entries with non-numeric
  /// ids that have not been backfilled. New entries
  /// always carry an explicit version.
  final int? version;

  /// The UTC instant at which the migration was
  /// applied, parsed from the ISO-8601 string in the
  /// `applied_at` column.
  final DateTime appliedAt;

  ///: creates an [AppliedMigration] from
  /// a raw row of the tracking table. The expected
  /// columns are `id`, `name`, `version`, `applied_at`.
  /// Tolerates older rows that pre-date the `version`
  /// column (the row map simply won't have a `version`
  /// key, which becomes `null`).
  factory AppliedMigration.fromRow(Map<String, Object?> row) {
    final Object? rawId = row['id'];
    final Object? rawName = row['name'];
    final Object? rawVersion = row['version'];
    final Object? rawAppliedAt = row['applied_at'];
    if (rawId is! String) {
      throw FormatException(
        'AppliedMigration.fromRow: `id` column is not a '
        'String (got ${rawId.runtimeType}). The row is '
        'probably from a different table.',
      );
    }
    if (rawName is! String) {
      throw FormatException(
        'AppliedMigration.fromRow: `name` column is not a '
        'String (got ${rawName.runtimeType}).',
      );
    }
    if (rawAppliedAt is! String) {
      throw FormatException(
        'AppliedMigration.fromRow: `applied_at` column is '
        'not a String (got ${rawAppliedAt.runtimeType}).',
      );
    }
    final DateTime applied = DateTime.parse(rawAppliedAt);
    final int? version = switch (rawVersion) {
      null => null,
      int v => v,
      String s => int.tryParse(s),
      num n => n.toInt(),
      Object _ => null,
    };
    return AppliedMigration._(
      id: rawId,
      name: rawName,
      version: version,
      appliedAt: applied,
    );
  }

  const AppliedMigration._({
    required this.id,
    required this.name,
    required this.version,
    required this.appliedAt,
  });

  ///: convenience constructor for tests and
  /// for users who build an [AppliedMigration] by hand
  /// (e.g. a custom CLI plugin).
  const AppliedMigration({
    required this.id,
    required this.name,
    required this.version,
    required this.appliedAt,
  });

  @override
  String toString() => 'AppliedMigration($id, $name, version: $version, '
      'appliedAt: ${appliedAt.toIso8601String()})';

  @override
  bool operator ==(Object other) =>
      other is AppliedMigration &&
      other.id == id &&
      other.name == name &&
      other.version == version &&
      other.appliedAt.isAtSameMomentAs(appliedAt);

  @override
  int get hashCode => Object.hash(id, name, version, appliedAt);
}
