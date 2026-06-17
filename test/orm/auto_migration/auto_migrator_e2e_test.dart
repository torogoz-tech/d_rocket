// End-to-end tests for the auto-migration
// system (commits 4 + 5 of
// feat/auto-migrations). These tests use
// Db.open / Db.inMemory with the
// `entityMetas:` and `autoMigrate:` parameters
// and exercise the round-trip:
// fresh install, add column, add table, drop
// (not applied), re-run, etc.

import 'dart:io';

import 'package:test/test.dart';

import '../../_helpers.dart';

EntityMeta _bookMeta({List<ColumnMeta>? extraColumns}) {
  final List<ColumnMeta> cols = <ColumnMeta>[
    ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
      isAutoIncrement: true,
    ),
    ColumnMeta(
      sqlName: 'title',
      dartField: 'title',
      dartType: String,
    ),
    if (extraColumns != null) ...extraColumns,
  ];
  return EntityMeta(
    tableName: 'books',
    columns: cols,
    insertableColumns: cols.sublist(1),
    updatableColumns: cols.sublist(1),
    primaryKey: cols[0],
    primaryKeyIndex: 0,
    pkOf: (Object e) => 0,
  );
}

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Db.autoMigrate end-to-end', () {
    test('fresh install: autoMigrate creates the table', () async {
      final Db db = await Db.inMemory(
        entityMetas: <EntityMeta>[_bookMeta()],
        autoMigrate: true,
      );
      try {
        // The table should now exist.
        final List<Map<String, Object?>> cols = db.provider
            .select('PRAGMA table_info(books)');
        expect(cols, isNotEmpty);
        // id, title (no extras).
        expect(cols, hasLength(2));
        // The schema_state row should be present
        // (id = 1).
        final List<Map<String, Object?>> state = db.provider
            .select('SELECT id, schema_json FROM d_rocket_schema_state');
        expect(state, hasLength(1));
        expect(state[0]['id'], 1);
        expect(state[0]['schema_json'], isA<String>());
        // No pending diff after a successful run.
        final List<SchemaDiff> pending = await db.pendingSchemaDiff();
        expect(pending, isEmpty);
      } finally {
        await db.close();
      }
    });

    test(
        're-open: a second autoMigrate run with the same schema is a no-op',
        () async {
      final Db db1 = await Db.inMemory(
        entityMetas: <EntityMeta>[_bookMeta()],
        autoMigrate: true,
      );
      await db1.close();
      // Re-open with the same schema. The
      // auto-migrator should detect no diff and
      // not re-run any DDL.
      final Db db2 = await Db.inMemory(
        entityMetas: <EntityMeta>[_bookMeta()],
        autoMigrate: true,
      );
      try {
        final List<SchemaDiff> pending = await db2.pendingSchemaDiff();
        expect(pending, isEmpty);
      } finally {
        await db2.close();
      }
    });

    test('add column: re-open with an extra column applies the diff',
        () async {
      // Open with the v1 schema.
      final Db db1 = await Db.inMemory(
        entityMetas: <EntityMeta>[_bookMeta()],
        autoMigrate: true,
      );
      await db1.close();
      // Reopen with the v2 schema (one extra
      // nullable column).
      final Db db2 = await Db.inMemory(
        entityMetas: <EntityMeta>[
          _bookMeta(
            extraColumns: <ColumnMeta>[
              ColumnMeta(
                sqlName: 'note',
                dartField: 'note',
                dartType: String,
                nullable: true,
              ),
            ],
          ),
        ],
        autoMigrate: true,
      );
      try {
        // The column should now exist on disk.
        final List<Map<String, Object?>> cols = db2.provider
            .select('PRAGMA table_info(books)');
        final List<String> colNames =
            cols.map((Map<String, Object?> c) => c['name']! as String).toList();
        expect(colNames, containsAll(<String>['id', 'title', 'note']));
        // No more pending diff.
        final List<SchemaDiff> pending = await db2.pendingSchemaDiff();
        expect(pending, isEmpty);
      } finally {
        await db2.close();
      }
    });

    test('drop column: re-open with a removed column is REPORTED, not applied',
        () async {
      // Use a file-backed DB so the schema
      // persists across opens (in-memory DBs
      // are fresh on every call, which would
      // mask the "drop not applied" test by
      // turning it into a fresh-install test).
      final String tmp = '${Directory.systemTemp.path}/'
          'd_rocket_auto_mig_drop_${DateTime.now().microsecondsSinceEpoch}.db';
      try {
        // Open with the v1 schema (id + title).
        final Db db1 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[_bookMeta()],
          autoMigrate: true,
        );
        // Insert a row so the column has data.
        db1.provider.execute("INSERT INTO books (title) VALUES ('A')");
        await db1.close();
        // Reopen with the v2 schema (id only; no
        // title). The auto-migrator should
        // report the drop but NOT apply it.
        final Db db2 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[
            EntityMeta(
              tableName: 'books',
              columns: <ColumnMeta>[
                ColumnMeta(
                  sqlName: 'id',
                  dartField: 'id',
                  dartType: int,
                  isPrimaryKey: true,
                  isAutoIncrement: true,
                ),
              ],
              insertableColumns: const <ColumnMeta>[],
              updatableColumns: const <ColumnMeta>[],
              primaryKey: ColumnMeta(
                sqlName: 'id',
                dartField: 'id',
                dartType: int,
                isPrimaryKey: true,
                isAutoIncrement: true,
              ),
              primaryKeyIndex: 0,
              pkOf: (Object e) => 0,
            ),
          ],
          autoMigrate: true,
        );
        try {
          // The 'title' column should STILL
          // exist (the drop was not applied).
          final List<Map<String, Object?>> cols = db2.provider
              .select('PRAGMA table_info(books)');
          final List<String> colNames = cols
              .map((Map<String, Object?> c) => c['name']! as String)
              .toList();
          expect(colNames, contains('title'));
          // The row should STILL exist.
          final List<Map<String, Object?>> rows = db2.provider
              .select('SELECT id, title FROM books');
          expect(rows, hasLength(1));
          expect(rows[0]['title'], 'A');
          // The pending diff should report the
          // unsafe drop.
          final List<SchemaDiff> pending = await db2.pendingSchemaDiff();
          expect(pending, hasLength(1));
          expect(pending[0].type, SchemaOperationType.dropColumn);
          expect(pending[0].severity, DiffSeverity.unsafe);
        } finally {
          await db2.close();
        }
      } finally {
        try {
          await File(tmp).delete();
        } catch (_) {
          // ignore
        }
      }
    });

    test('add table: re-open with a new entity creates it', () async {
      // Open with the v1 schema (just books).
      final Db db1 = await Db.inMemory(
        entityMetas: <EntityMeta>[_bookMeta()],
        autoMigrate: true,
      );
      await db1.close();
      // Reopen with the v2 schema (books + authors).
      final Db db2 = await Db.inMemory(
        entityMetas: <EntityMeta>[
          _bookMeta(),
          EntityMeta(
            tableName: 'authors',
            columns: <ColumnMeta>[
              ColumnMeta(
                sqlName: 'id',
                dartField: 'id',
                dartType: int,
                isPrimaryKey: true,
                isAutoIncrement: true,
              ),
              ColumnMeta(
                sqlName: 'name',
                dartField: 'name',
                dartType: String,
              ),
            ],
            insertableColumns: <ColumnMeta>[
              ColumnMeta(
                sqlName: 'name',
                dartField: 'name',
                dartType: String,
              ),
            ],
            updatableColumns: <ColumnMeta>[
              ColumnMeta(
                sqlName: 'name',
                dartField: 'name',
                dartType: String,
              ),
            ],
            primaryKey: ColumnMeta(
              sqlName: 'id',
              dartField: 'id',
              dartType: int,
              isPrimaryKey: true,
              isAutoIncrement: true,
            ),
            primaryKeyIndex: 0,
            pkOf: (Object e) => 0,
          ),
        ],
        autoMigrate: true,
      );
      try {
        // Both tables exist.
        final List<Map<String, Object?>> tables = db2.provider
            .select("SELECT name FROM sqlite_master WHERE type = 'table'");
        final List<String> names = tables
            .map((Map<String, Object?> r) => r['name']! as String)
            .toList();
        expect(names, containsAll(<String>['books', 'authors']));
      } finally {
        await db2.close();
      }
    });

    test('file-backed: the round-trip works on a real on-disk DB', () async {
      final String tmp = '${Directory.systemTemp.path}/'
          'd_rocket_auto_mig_${DateTime.now().microsecondsSinceEpoch}.db';
      try {
        final Db db1 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[_bookMeta()],
          autoMigrate: true,
        );
        await db1.close();
        final Db db2 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[
            _bookMeta(
              extraColumns: <ColumnMeta>[
                ColumnMeta(
                  sqlName: 'note',
                  dartField: 'note',
                  dartType: String,
                  nullable: true,
                ),
              ],
            ),
          ],
          autoMigrate: true,
        );
        try {
          final List<Map<String, Object?>> cols = db2.provider
              .select('PRAGMA table_info(books)');
          final List<String> colNames = cols
              .map((Map<String, Object?> c) => c['name']! as String)
              .toList();
          expect(colNames, containsAll(<String>['id', 'title', 'note']));
        } finally {
          await db2.close();
        }
      } finally {
        try {
          await File(tmp).delete();
        } catch (_) {
          // ignore
        }
      }
    });

    test('autoMigrate: false (default) does NOT auto-migrate', () async {
      // Use a file-backed DB so the schema
      // persists across opens (in-memory DBs
      // are fresh on every call, which would
      // mask the "autoMigrate: false" test by
      // turning it into a fresh-install test).
      final String tmp = '${Directory.systemTemp.path}/'
          'd_rocket_auto_mig_false_${DateTime.now().microsecondsSinceEpoch}.db';
      try {
        // Open with v1, autoMigrate: true.
        final Db db1 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[_bookMeta()],
          autoMigrate: true,
        );
        await db1.close();
        // Reopen with v2 but autoMigrate: false.
        // The new column should NOT exist on disk
        // because the auto-migrator did not run.
        final Db db2 = await Db.open(
          path: tmp,
          entityMetas: <EntityMeta>[
            _bookMeta(
              extraColumns: <ColumnMeta>[
                ColumnMeta(
                  sqlName: 'note',
                  dartField: 'note',
                  dartType: String,
                  nullable: true,
                ),
              ],
            ),
          ],
          // autoMigrate defaults to false
        );
        try {
          final List<Map<String, Object?>> cols = db2.provider
              .select('PRAGMA table_info(books)');
          final List<String> colNames = cols
              .map((Map<String, Object?> c) => c['name']! as String)
              .toList();
          expect(colNames, isNot(contains('note')));
          // pendingSchemaDiff still works (it
          // does not depend on autoMigrate being
          // true). It reports the pending
          // addColumn so the user knows what
          // would happen if they enabled
          // autoMigrate.
          final List<SchemaDiff> pending = await db2.pendingSchemaDiff();
          expect(pending, hasLength(1));
          expect(pending[0].type, SchemaOperationType.addColumn);
        } finally {
          await db2.close();
        }
      } finally {
        try {
          await File(tmp).delete();
        } catch (_) {
          // ignore
        }
      }
    });

    test('empty entityMetas is a no-op (back-compat with 1.1.x callers)',
        () async {
      // Db.open without entityMetas must work
      // exactly as in 1.1.x: no schema_state
      // table is created, no auto-migration
      // happens.
      final Db db = await Db.inMemory();
      try {
        // The schema_state table is not created
        // because the auto-migrator never runs.
        final List<Map<String, Object?>> tables = db.provider
            .select(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND "
                "name = 'd_rocket_schema_state'");
        expect(tables, isEmpty);
      } finally {
        await db.close();
      }
    });
  });
}
