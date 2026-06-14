/// — `MigrationStrategy`:
///
/// The ADO.NET / sqflite_common_ffi / EF Core way of
/// declaring migrations. Replaces the
/// `DbContext.migrations` list with a
/// version-tagged, callback-driven declaration:
///
/// ```dart
/// await Db.open(
/// path: 'app.db',
/// strategy: MigrationStrategy(
/// version: 5,
/// migrations: `<MigrationBase>`[
/// M001CreateUsers,
/// M002AddEmail,
/// M003AddPosts,
/// M004AddPostAuthorId,
/// M005CreateSessions,
///],
///),
///);
/// ```
///
/// The runner inspects the version of the database
/// (stored in `_d_rocket_migrations.version`) and
/// either:
///
/// * applies all migrations (`fresh` install),
/// * applies the subset in `(current, version]`
/// (`upgrade`),
/// * rolls back the subset in `(version, current]`
/// in reverse (`downgrade`),
/// * or is a no-op (`current == version`).
///
/// Two execution modes:
///
/// 1. Declarative (default): pass the full
/// `migrations` list and the runner picks the
/// subset based on `version`. The runner records
/// each applied migration in the tracking table.
///
/// 2. Imperative (sqflite-style): pass the
/// `onUpgrade(exec, oldV, newV)` callback. The
/// user is responsible for the branching logic
/// (`if (oldV < 2) await M002.upAsync(exec); …`).
/// Set `trackMigrations: false` to skip the runner's
/// auto-tracking and let the user manage the table
/// manually.
library;

import 'migration.dart';
import 'migration_executor.dart';

///: a version-tagged, callback-driven
/// migration declaration. The `version` is the
/// target schema version (not the number of
/// migrations applied). On a fresh install the runner
/// applies every migration whose `version` is `<= this.version`.
class MigrationStrategy {
  ///: the target schema version. After
  /// running this strategy, the database is at this
  /// version.
  final int version;

  ///: the full, ordered list of available
  /// migrations. The runner picks the subset to apply
  /// / rollback based on `version` and the database's
  /// current version.
  ///
  /// Required for declarative mode. Ignored
  /// when [onCreate] / [onUpgrade] / [onDowngrade] are
  /// provided (imperative mode).
  final List<MigrationBase> migrations;

  ///: imperative-mode callback. Invoked
  /// once when the database is created for the first
  /// time. By default (in declarative mode) the runner
  /// applies every migration in [migrations] in order.
  final Future<void> Function(
    MigrationExecutor exec,
    int version,
  )? onCreate;

  ///: imperative-mode callback. Invoked
  /// when the database is being upgraded from
  /// [oldVersion] (0 ≤ oldV < newV). The user
  /// typically branches on `oldV`:
  ///
  /// ```dart
  /// onUpgrade: (exec, oldV, newV) async {
  /// if (oldV < 2) await M002AddEmail.upAsync(exec);
  /// if (oldV < 3) await M003AddPosts.upAsync(exec);
  /// },
  /// ```
  ///
  /// By default the runner auto-picks the migrations
  /// in `migrations` whose `version` is in
  /// `(oldV, newV]` and runs them in order.
  final Future<void> Function(
    MigrationExecutor exec,
    int oldVersion,
    int newVersion,
  )? onUpgrade;

  ///: imperative-mode callback. Invoked
  /// when the database is being downgraded from
  /// [oldVersion] (newV < oldV). The user typically
  /// branches on `oldV`:
  ///
  /// ```dart
  /// onDowngrade: (exec, oldV, newV) async {
  /// if (oldV > 2) await M002AddEmail.downAsync(exec);
  /// if (oldV > 1) await M001CreateUsers.downAsync(exec);
  /// },
  /// ```
  ///
  /// By default the runner auto-picks the migrations
  /// in `migrations` whose `version` is in
  /// `(newV, oldV]` and rolls them back in reverse
  /// order.
  ///
  ///: a `null` [onDowngrade] (and absent
  /// declarative `down`) leaves downgrades as a
  /// `StateError` — the user is expected to either
  /// provide a callback or override the
  /// `MigrationBase.down` body.
  final Future<void> Function(
    MigrationExecutor exec,
    int oldVersion,
    int newVersion,
  )? onDowngrade;

  ///: when `true` (default in declarative
  /// mode), the runner records each applied migration
  /// in the `_d_rocket_migrations` table. When
  /// `false` (default in imperative mode with
  /// [onCreate] / [onUpgrade]), the user is responsible
  /// for the table.
  final bool trackMigrations;

  const MigrationStrategy({
    required this.version,
    this.migrations = const <MigrationBase>[],
    this.onCreate,
    this.onUpgrade,
    this.onDowngrade,
    this.trackMigrations = true,
  });

  ///: `true` when the strategy uses
  /// imperative callbacks ([onCreate] / [onUpgrade] /
  /// [onDowngrade]) and `false` when it uses the
  /// declarative [migrations] list. Computed once
  /// from the constructor arguments.
  bool get isImperative =>
      onCreate != null || onUpgrade != null || onDowngrade != null;

  @override
  String toString() => 'MigrationStrategy(version: $version, '
      'mode: ${isImperative ? "imperative" : "declarative"}, '
      'migrations: ${migrations.length})';
}
