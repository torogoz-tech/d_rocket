///: abstract base for a code-first
/// migration. Subclass this and implement [up] (and
/// optionally [down]). The [MigrationRunner] iterates
/// the list of migrations in lexicographic order
/// of [id].
///
/// **Naming note**: the public user-facing
/// *annotation* that marks a top-level function as a
/// code-first migration is `@Migration` (defined in
/// `rocket_migration.dart`). The annotation emits a
/// concrete subclass of THIS class (renamed from
/// `MigrationBase` to `MigrationBase` to avoid the
/// same-library collision with the annotation
/// class). User code therefore reads:
///
/// ```dart
/// @Migration(id: '001', name: 'Initial schema')
/// MigrationBase initialSchema => _$_InitialSchema;
/// ```
///
/// ...where `_$_InitialSchema extends MigrationBase`
/// and implements `up` / `down` from the codegen
/// output. The codegen updates emitted in a future
/// build will use `MigrationBase` as the superclass
/// name; existing user code that already uses
/// `MigrationBase` as the superclass must be updated.
///
/// The [version] getter is the new
/// monotonic `int` identifier used by
/// [MigrationStrategy]. The default parses [id] as an
/// `int` for backward-compat with the pre—10
/// String-id style (`'001'`, `'002'`, …). Override
/// [version] explicitly for non-numeric ids (e.g.
/// date-based `'-'`).
///
/// Callback signatures (typedefs) live in their own
/// files:
/// - `MigrationExecutor` → migration_executor.dart
/// - `MigrationSelector` → migration_selector.dart
/// - `AsyncMigrationExecutor` → async_migration_executor.dart
/// - `AsyncMigrationSelector` → async_migration_selector.dart
library;

import 'async_migration_executor.dart';
import 'migration_executor.dart';

/// Abstract base for a code-first migration. The
/// user-facing annotation `@Migration` (in
/// `rocket_migration.dart`) generates a concrete
/// subclass of this class.
abstract class MigrationBase {
  /// Stable, lexicographically-ordered identifier.
  /// Used as the primary key in the
  /// `_d_rocket_migrations` tracking table.
  String get id;

  /// Human-readable name. Shown in the
  /// `_d_rocket_migrations` table and in error
  /// messages.
  String get name;

  ///: monotonic `int` schema version.
  /// Used by [MigrationStrategy] to pick the subset
  /// of migrations to apply on upgrade / rollback.
  ///
  /// The default parses [id] as an `int`. For
  /// date-based ids (e.g. `'-'`),
  /// override this to return the monotonic
  /// version explicitly.
  ///
  /// Throws [StateError] when the override is missing
  /// AND the [id] is not parseable as an `int`.
  int get version {
    final int? parsed = int.tryParse(id);
    if (parsed == null) {
      throw StateError(
        'MigrationBase "$id" ($name) has a non-numeric id '
        'and no explicit `version` override. The Fase 10 '
        'MigrationStrategy API requires a monotonic int '
        'version — override `version` to enable '
        '`migrateTo(...)` / `onUpgrade(oldV, newV)` '
        'dispatch.',
      );
    }
    return parsed;
  }

  /// Apply this migration to the database. Receives
  /// a [MigrationExecutor].
  void up(MigrationExecutor exec);

  /// Reverse this migration. Optional — the MVP
  /// allows the default (throws) when a migration is
  /// intentionally irreversible.
  void down(MigrationExecutor exec) {
    throw UnsupportedError(
      'MigrationBase "$id" ($name) is irreversible. '
      'Override `down()` to enable rollback.',
    );
  }

  /// (async): the async counterpart
  /// of [up].
  Future<void> upAsync(AsyncMigrationExecutor exec) async {
    up((String sql, [List<Object?>? binds]) {
      exec(sql, binds);
    });
  }

  /// (async): the async counterpart
  /// of [down].
  Future<void> downAsync(AsyncMigrationExecutor exec) async {
    down((String sql, [List<Object?>? binds]) {
      exec(sql, binds);
    });
  }

  @override
  String toString() => 'MigrationBase($id, $name)';
}
