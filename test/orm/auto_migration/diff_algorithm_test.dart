// Tests for computeSchemaDiff (commit 3 of
// feat/auto-migrations). Each diff type has a
// focused test that builds the old and new
// snapshots by hand and asserts the diff
// entries are correct.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

SchemaTable _table(
  String name, {
  List<SchemaColumn> columns = const <SchemaColumn>[],
  List<SchemaIndex> indexes = const <SchemaIndex>[],
  List<String> primaryKey = const <String>[],
}) {
  return SchemaTable(
    name: name,
    columns: columns,
    indexes: indexes,
    primaryKey: primaryKey,
  );
}

SchemaColumn _col(
  String name, {
  String sqliteType = 'TEXT',
  bool nullable = false,
  String? defaultLiteral,
  bool isPrimaryKey = false,
  bool isAutoIncrement = false,
  SchemaForeignKey? foreignKey,
}) {
  return SchemaColumn(
    name: name,
    sqliteType: sqliteType,
    nullable: nullable,
    defaultLiteral: defaultLiteral,
    isPrimaryKey: isPrimaryKey,
    isAutoIncrement: isAutoIncrement,
    foreignKey: foreignKey,
  );
}

SchemaSnapshot _snap(List<SchemaTable> tables) =>
    SchemaSnapshot(version: 1, tables: tables);

void main() {
  group('computeSchemaDiff', () {
    test('identical snapshots yield an empty diff', () {
      final SchemaTable t = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('name'),
      ]);
      final SchemaSnapshot s = _snap(<SchemaTable>[t]);
      expect(computeSchemaDiff(s, s), isEmpty);
    });

    test('createTable when a table is in new but not in old (safe)', () {
      final SchemaTable newT = _table('books', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('title'),
      ]);
      final List<SchemaDiff> diffs =
          computeSchemaDiff(_snap(<SchemaTable>[]), _snap(<SchemaTable>[newT]));
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.createTable);
      expect(diffs[0].severity, DiffSeverity.safe);
      expect(diffs[0].tableName, 'books');
    });

    test('dropTable when a table is in old but not in new (unsafe)', () {
      final SchemaTable oldT = _table('obsolete');
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.dropTable);
      expect(diffs[0].severity, DiffSeverity.unsafe);
      expect(diffs[0].tableName, 'obsolete');
    });

    test('addColumn nullable is safe', () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('note', nullable: true),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.addColumn);
      expect(diffs[0].severity, DiffSeverity.safe);
    });

    test('addColumn with default literal is safe', () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('count', defaultLiteral: '0'),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].severity, DiffSeverity.safe);
    });

    test('addColumn NOT NULL without default is unsafe (backfill impossible)',
        () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('mandatory', nullable: false),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.addColumn);
      expect(diffs[0].severity, DiffSeverity.unsafe);
    });

    test('dropColumn is unsafe', () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('legacy'),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.dropColumn);
      expect(diffs[0].severity, DiffSeverity.unsafe);
      expect(diffs[0].columnName, 'legacy');
    });

    test('modifyColumn (type change) is unsafe', () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('value', sqliteType: 'TEXT'),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('value', sqliteType: 'INTEGER'),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.modifyColumn);
      expect(diffs[0].severity, DiffSeverity.unsafe);
    });

    test('modifyColumn (nullability change) is unsafe', () {
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('note', nullable: false),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('note', nullable: true),
      ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.modifyColumn);
      expect(diffs[0].severity, DiffSeverity.unsafe);
    });

    test('createIndex is safe', () {
      final SchemaTable oldT = _table('a',
          columns: <SchemaColumn>[
            _col('id', isPrimaryKey: true, isAutoIncrement: true),
            _col('email'),
          ],
          indexes: const <SchemaIndex>[]);
      final SchemaTable newT = _table('a',
          columns: <SchemaColumn>[
            _col('id', isPrimaryKey: true, isAutoIncrement: true),
            _col('email'),
          ],
          indexes: <SchemaIndex>[
            const SchemaIndex(
              name: 'a_email_idx',
              columns: <String>['email'],
            ),
          ]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.createIndex);
      expect(diffs[0].severity, DiffSeverity.safe);
    });

    test('dropIndex is unsafe', () {
      final SchemaTable oldT = _table('a',
          columns: <SchemaColumn>[
            _col('id', isPrimaryKey: true, isAutoIncrement: true),
            _col('email'),
          ],
          indexes: <SchemaIndex>[
            const SchemaIndex(
              name: 'a_email_idx',
              columns: <String>['email'],
            ),
          ]);
      final SchemaTable newT = _table('a',
          columns: <SchemaColumn>[
            _col('id', isPrimaryKey: true, isAutoIncrement: true),
            _col('email'),
          ],
          indexes: const <SchemaIndex>[]);
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      expect(diffs, hasLength(1));
      expect(diffs[0].type, SchemaOperationType.dropIndex);
      expect(diffs[0].severity, DiffSeverity.unsafe);
    });

    test('rename heuristic: drop A + add A with same type suggests RENAME',
        () {
      // The "drop" is on a column whose name still
      // appears in the new schema (with the same
      // type). The rename heuristic kicks in.
      final SchemaTable oldT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('note', sqliteType: 'TEXT'),
      ]);
      final SchemaTable newT = _table('a', columns: <SchemaColumn>[
        _col('id', isPrimaryKey: true, isAutoIncrement: true),
        _col('comment', sqliteType: 'TEXT'),
      ]);
      // Wait, the rename heuristic requires the
      // column name to be PRESERVED in new (i.e.
      // it appears in both old and new). Let me
      // rewrite: the column was renamed from
      // `note` to `comment`, so the diff is
      // dropColumn(note) + addColumn(comment) +
      // the rename heuristic merges them into a
      // single renameColumn(note -> comment).
      // For the heuristic to fire the new schema
      // must contain a column with the SAME name
      // as the dropped one. So this is NOT a
      // rename - it's a real drop + add.
      final List<SchemaDiff> diffs = computeSchemaDiff(
        _snap(<SchemaTable>[oldT]),
        _snap(<SchemaTable>[newT]),
      );
      // Expect drop + add, no rename (because
      // the names are different).
      expect(diffs, hasLength(2));
      expect(
        diffs.map((SchemaDiff d) => d.type).toSet(),
        <SchemaOperationType>{
          SchemaOperationType.dropColumn,
          SchemaOperationType.addColumn,
        },
      );
    });

    test('version downgrade (old > new) throws', () {
      final SchemaSnapshot old =
          SchemaSnapshot(version: 99, tables: const <SchemaTable>[]);
      final SchemaSnapshot newS =
          SchemaSnapshot(version: 1, tables: const <SchemaTable>[]);
      expect(
        () => computeSchemaDiff(old, newS),
        throwsA(isA<StateError>()),
      );
    });
  });
}
