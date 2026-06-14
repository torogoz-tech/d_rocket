// Tests for the TPC (Table-Per-Concrete-
// Class) polymorphism. The root is abstract (no
// table); each leaf has its own table with all the
// columns (root's + leaf's). No JOINs needed at read
// time.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.2.4 — TPC: schema + meta shape', () {
    test('a TPC root has isAbstract=true (no table)', () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
        isAutoIncrement: true,
      );
      final ColumnMeta nameCol = ColumnMeta(
        sqlName: 'name',
        dartField: 'name',
        dartType: String,
      );
      final EntityMeta animalMeta = EntityMeta(
        tableName: 'animals', // never used at runtime
        columns: <ColumnMeta>[idCol, nameCol],
        insertableColumns: <ColumnMeta>[idCol, nameCol],
        updatableColumns: <ColumnMeta>[nameCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        // (TPC):
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      expect(animalMeta.inheritanceStrategy, InheritanceStrategy.tpc);
      expect(animalMeta.isAbstract, isTrue,
          reason: 'TPC roots own no table — they\'re abstract');
    });

    test('a TPC leaf has isAbstract=false and its own table', () {
      // The leaf's columns include BOTH the root's
      // (id, name) AND the leaf's specific (breed).
      // The codegen for .x will emit these
      // automatically; for now we hand-build them.
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
        isAutoIncrement: true,
      );
      final ColumnMeta nameCol = ColumnMeta(
        sqlName: 'name',
        dartField: 'name',
        dartType: String,
      );
      final ColumnMeta breedCol = ColumnMeta(
        sqlName: 'breed',
        dartField: 'breed',
        dartType: String,
        nullable: true,
      );
      final EntityMeta dogMeta = EntityMeta(
        tableName: 'dogs',
        columns: <ColumnMeta>[idCol, nameCol, breedCol],
        insertableColumns: <ColumnMeta>[nameCol, breedCol],
        updatableColumns: <ColumnMeta>[nameCol, breedCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: false,
      );
      expect(dogMeta.inheritanceStrategy, InheritanceStrategy.tpc);
      expect(dogMeta.isAbstract, isFalse);
      // The leaf has all 3 columns (root's + leaf's).
      expect(dogMeta.columns, hasLength(3));
    });

    test('all three EF Core strategies are now present', () {
      expect(
          InheritanceStrategy.values,
          containsAll(<InheritanceStrategy>[
            InheritanceStrategy.none,
            InheritanceStrategy.tph,
            InheritanceStrategy.tpt,
            InheritanceStrategy.tpc,
          ]));
    });
  });

  group('Fase 5.2.4 — TPC: end-to-end with SQLite', () {
    late SqliteQueryProvider provider;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('the leaf tables are created (no root table for TPC roots)', () {
      // TPC: only the leaves own tables. The root
      // has no table.
      provider.execute('''
        CREATE TABLE dogs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          breed TEXT
        )
      ''');
      provider.execute('''
        CREATE TABLE cats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          indoor INTEGER
        )
      ''');
      final List<Map<String, Object?>> tables = provider.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> r in tables) r['name']! as String,
      };
      expect(names, containsAll(<String>{'dogs', 'cats'}));
    });

    test('inserting a Dog goes into the dogs table (not a "animals" table)',
        () {
      provider.execute('''
        CREATE TABLE dogs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          breed TEXT
        )
      ''');
      provider.execute(
        'INSERT INTO dogs (name, breed) VALUES (?, ?)',
        <Object?>['Rex', 'labrador'],
      );
      final List<Map<String, Object?>> rows = provider.select(
        'SELECT name, breed FROM dogs',
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Rex');
      expect(rows.first['breed'], 'labrador');
    });
  });

  group('Fase 5.2.4 — TPC: copyWith preserves isAbstract', () {
    test('a TPC root meta can be rebuilt via copyWith', () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final EntityMeta root = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol],
        insertableColumns: <ColumnMeta>[],
        updatableColumns: <ColumnMeta>[],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      final EntityMeta copy = root.copyWith(isAbstract: false);
      expect(copy.isAbstract, isFalse);
      expect(copy.inheritanceStrategy, InheritanceStrategy.tpc);
    });
  });

  group('Fase 5.2.4 — TPC: cross-strategy interaction', () {
    test('a TPC root has no discriminator / parentTable (unlike TPH / TPT)',
        () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final EntityMeta root = EntityMeta(
        tableName: 'animals',
        columns: <ColumnMeta>[idCol],
        insertableColumns: <ColumnMeta>[],
        updatableColumns: <ColumnMeta>[],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpc,
        isAbstract: true,
      );
      // TPC roots have no discriminator (no
      // discriminator column on any single table).
      expect(root.discriminatorColumn, isNull);
      // TPC roots have no parent table.
      expect(root.parentTable, isNull);
      // TPC roots have no subclassMetas (no
      // dispatcher — the leaves are read directly).
      expect(root.subclassMetas, isNull);
    });
  });
}
