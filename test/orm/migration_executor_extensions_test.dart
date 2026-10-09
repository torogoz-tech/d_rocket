import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('emits safe quoted ALTER TABLE helpers', () {
    final statements = <String>[];
    void execute(String sql, [List<Object?>? _]) => statements.add(sql);

    execute.addColumn('events', 'createdAt', 'TEXT NOT NULL');
    execute.renameTable('events', 'archived_events');
    execute.renameColumn('archived_events', 'createdAt', 'created_at');
    execute.dropTableIfExists('legacy_events');
    execute.dropIndexIfExists('events_created_at');
    execute.createIndex('events_created_at', 'events', '"created_at"');

    expect(statements, <String>[
      'ALTER TABLE "events" ADD COLUMN "createdAt" TEXT NOT NULL',
      'ALTER TABLE "events" RENAME TO "archived_events"',
      'ALTER TABLE "archived_events" RENAME COLUMN "createdAt" TO "created_at"',
      'DROP TABLE IF EXISTS "legacy_events"',
      'DROP INDEX IF EXISTS "events_created_at"',
      'CREATE INDEX "events_created_at" ON "events" ("created_at")',
    ]);
  });

  test('emits an explicit table rebuild plan', () {
    final statements = <String>[];
    void execute(String sql, [List<Object?>? _]) => statements.add(sql);

    execute.rebuildTable(
      'events',
      'CREATE TABLE "events" ("id" TEXT PRIMARY KEY, "amount" REAL)',
      columns: <String>['id'],
    );

    expect(statements, <String>[
      'ALTER TABLE "events" RENAME TO "events__d_rocket_old"',
      'CREATE TABLE "events" ("id" TEXT PRIMARY KEY, "amount" REAL)',
      'INSERT INTO "events" ("id") SELECT "id" FROM "events__d_rocket_old"',
      'DROP TABLE "events__d_rocket_old"',
    ]);
  });

  test('rejects unsafe identifiers before emitting SQL', () {
    final statements = <String>[];
    void execute(String sql, [List<Object?>? _]) => statements.add(sql);

    expect(
      () => execute.dropTableIfExists('events"; DROP TABLE users; --'),
      throwsArgumentError,
    );
    expect(statements, isEmpty);
  });
}
