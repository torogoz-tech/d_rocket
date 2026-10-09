import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

import '../fixtures/generated_destructive_migration.dart';
import '../fixtures/generated_schema_migration.dart';
import 'package:d_rocket/src/cli/migration_codegen.dart';

void main() {
  group('generated migration SQL against SQLite', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
    });

    tearDown(() {
      provider.dispose();
    });

    test('executes generated CREATE, ADD, RENAME, INDEX and DROP SQL', () {
      final GeneratedSchemaMigration migration = GeneratedSchemaMigration();

      migration.up(provider.execute);

      final List<Map<String, Object?>> columns = provider.select(
        'PRAGMA table_info(events)',
      );
      expect(
        columns.map((Map<String, Object?> row) => row['name']),
        containsAll(<Object?>['id', 'description', 'amount']),
      );

      final List<Map<String, Object?>> indexes = provider.select(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'index' AND name = 'idx_events_description'",
      );
      expect(indexes, hasLength(1));

      migration.down(provider.execute);

      final List<Map<String, Object?>> tables = provider.select(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = 'events'",
      );
      expect(tables, isEmpty);
    });

    test('executes generated destructive DROP TABLE SQL', () {
      provider.execute(
        'CREATE TABLE legacy_events (id INTEGER PRIMARY KEY)',
      );

      GeneratedDestructiveMigration().up(provider.execute);

      final List<Map<String, Object?>> tables = provider.select(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name = 'legacy_events'",
      );
      expect(tables, isEmpty);
    });

    test('manual-only generated changes do not become executable SQL', () {
      const CliSchemaDiff diff = CliSchemaDiff(
        severity: 'unsafe',
        type: 'modifyColumn',
        tableName: 'events',
        columnName: 'amount',
        sql: '-- (no direct ALTER COLUMN in SQLite; manual migration required)',
        reason: 'type changed',
      );

      final String source = buildMigrationFileContent(
        className: 'M003ModifyEventAmount',
        id: '003',
        name: 'modify event amount',
        diffs: const <CliSchemaDiff>[diff],
      );

      expect(source, contains('MANUAL REQUIRED: modifyColumn'));
      expect(source, isNot(contains("exec(r'''--")));
    });
  });
}
