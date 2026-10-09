import 'package:d_rocket/d_rocket.dart';

/// Fixture representative of the source emitted by migration codegen.
class GeneratedSchemaMigration extends MigrationBase {
  @override
  String get id => '001';

  @override
  String get name => 'create and alter events';

  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE events (id INTEGER PRIMARY KEY, note TEXT)');
    exec('ALTER TABLE events ADD COLUMN amount REAL');
    exec('ALTER TABLE events RENAME COLUMN note TO description');
    exec('CREATE INDEX idx_events_description ON events(description)');
  }

  @override
  void down(MigrationExecutor exec) {
    exec('DROP INDEX idx_events_description');
    exec('ALTER TABLE events RENAME COLUMN description TO note');
    exec('ALTER TABLE events DROP COLUMN amount');
    exec('DROP TABLE events');
  }
}
