import 'package:d_rocket/d_rocket.dart';

/// Fixture representative of generated destructive SQL.
class GeneratedDestructiveMigration extends MigrationBase {
  @override
  String get id => '002';

  @override
  String get name => 'remove legacy data';

  @override
  void up(MigrationExecutor exec) {
    exec('DROP TABLE legacy_events');
  }

  @override
  void down(MigrationExecutor exec) {
    // A dropped table has no data-preserving generated inverse.
    throw UnsupportedError('legacy_events cannot be restored automatically');
  }
}
