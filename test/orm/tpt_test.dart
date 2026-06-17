// Tests for the TPT (Table-Per-Type)
// polymorphism. Animal → Dog / Cat with a separate
// `dogs` and `cats` table for each child. The child's
// table has the child's specific columns + a FK
// (`animal_id`) to the root's `animals` table.

import '../_helpers.dart';
import 'package:test/test.dart';

void main() {
  setUp(dRocketSqlite);
  tearDown(EngineRegistry.resetForTest);
  group('Fase 5.2.3 — TPT: schema + meta shape', () {
    test('a TPT child has parentTable + joinedFkColumn set', () {
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
      final ColumnMeta animalIdCol = ColumnMeta(
        sqlName: 'animal_id',
        dartField: 'animalId',
        dartType: int,
      );
      final ColumnMeta breedCol = ColumnMeta(
        sqlName: 'breed',
        dartField: 'breed',
        dartType: String,
        nullable: true,
      );
      final EntityMeta dogMeta = EntityMeta(
        tableName: 'dogs',
        columns: <ColumnMeta>[idCol, nameCol, animalIdCol, breedCol],
        insertableColumns: <ColumnMeta>[idCol, nameCol, animalIdCol, breedCol],
        updatableColumns: <ColumnMeta>[nameCol, animalIdCol, breedCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        // (TPT):
        inheritanceStrategy: InheritanceStrategy.tpt,
        parentTable: 'animals',
        joinedFkColumn: animalIdCol,
      );
      expect(dogMeta.inheritanceStrategy, InheritanceStrategy.tpt);
      expect(dogMeta.parentTable, 'animals');
      expect(dogMeta.joinedFkColumn, isNotNull);
      expect(dogMeta.joinedFkColumn!.sqlName, 'animal_id');
    });

    test('a TPT root has the tpt strategy + no parentTable', () {
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
        tableName: 'animals',
        columns: <ColumnMeta>[idCol, nameCol],
        insertableColumns: <ColumnMeta>[nameCol],
        updatableColumns: <ColumnMeta>[nameCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpt,
      );
      expect(animalMeta.inheritanceStrategy, InheritanceStrategy.tpt);
      expect(animalMeta.parentTable, isNull,
          reason: 'a TPT root has no parent table');
      expect(animalMeta.joinedFkColumn, isNull);
    });

    test('TPH and TPT strategies are distinct', () {
      expect(InheritanceStrategy.tpt, isNot(InheritanceStrategy.tph));
      expect(
          InheritanceStrategy.values,
          containsAll(<InheritanceStrategy>[
            InheritanceStrategy.none,
            InheritanceStrategy.tph,
            InheritanceStrategy.tpt,
          ]));
    });
  });

  group('Fase 5.2.3 — TPT: end-to-end with SQLite', () {
    late SqliteQueryProvider provider;
    late _ZooContext ctx;

    setUp(() {
      provider = SqliteQueryProvider.inMemory();
      provider.execute('PRAGMA foreign_keys = ON;');
      ctx = _ZooContext(provider);
      ctx.createSchema();
    });

    tearDown(() async {
      await provider.disposeAsync();
    });

    test('the animals + dogs + cats tables are created', () {
      final List<Map<String, Object?>> tables = provider.select(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      );
      final Set<String> names = <String>{
        for (final Map<String, Object?> r in tables) r['name']! as String,
      };
      expect(names, containsAll(<String>{'animals', 'dogs', 'cats'}));
    });

    test('the dogs table has a FK column (animal_id) to animals', () {
      final List<Map<String, Object?>> rows = provider.select(
        'PRAGMA table_info(dogs)',
      );
      final List<String> columnNames = <String>[
        for (final Map<String, Object?> r in rows) r['name']! as String,
      ];
      expect(columnNames,
          containsAll(<String>['id', 'name', 'animal_id', 'breed']));
    });

    test('inserting an animal + a dog with the same id links them via FK', () {
      provider.execute(
        'INSERT INTO animals (id, name) VALUES (1, ?)',
        <Object?>['Rex'],
      );
      provider.execute(
        'INSERT INTO dogs (id, name, animal_id, breed) VALUES (1, ?, ?, ?)',
        <Object?>['Rex', 1, 'labrador'],
      );
      // The dog can be read back from the dogs table
      // joined with the animals table.
      final List<Map<String, Object?>> rows = provider.selectWithBinds(
        'SELECT a.id, a.name, d.breed FROM animals a '
        'JOIN dogs d ON d.animal_id = a.id '
        'WHERE a.id = ?',
        <Object?>[1],
      );
      expect(rows, hasLength(1));
      expect(rows.first['name'], 'Rex');
      expect(rows.first['breed'], 'labrador');
    });
  });

  group('Fase 5.2.3 — TPT: copyWith preserves TPT fields', () {
    test('a TPT child meta can be rebuilt via copyWith', () {
      final ColumnMeta idCol = ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      );
      final ColumnMeta animalIdCol = ColumnMeta(
        sqlName: 'animal_id',
        dartField: 'animalId',
        dartType: int,
      );
      final EntityMeta child = EntityMeta(
        tableName: 'dogs',
        columns: <ColumnMeta>[idCol, animalIdCol],
        insertableColumns: <ColumnMeta>[idCol, animalIdCol],
        updatableColumns: <ColumnMeta>[idCol, animalIdCol],
        primaryKey: idCol,
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        inheritanceStrategy: InheritanceStrategy.tpt,
        parentTable: 'animals',
        joinedFkColumn: animalIdCol,
      );
      final EntityMeta copy = child.copyWith(parentTable: 'mammals');
      expect(copy.parentTable, 'mammals');
      expect(copy.joinedFkColumn, same(animalIdCol));
      expect(copy.inheritanceStrategy, InheritanceStrategy.tpt);
    });
  });
}

class _ZooContext {
  _ZooContext(this._provider);
  final SqliteQueryProvider _provider;

  void createSchema() {
    // TPT: the root owns its own table.
    _provider.execute('''
      CREATE TABLE animals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');
    // TPT: each child has its own table + a FK
    // to the root's PK.
    _provider.execute('''
      CREATE TABLE dogs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        animal_id INTEGER NOT NULL,
        breed TEXT,
        FOREIGN KEY (animal_id) REFERENCES animals(id)
      )
    ''');
    _provider.execute('''
      CREATE TABLE cats (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        animal_id INTEGER NOT NULL,
        indoor INTEGER,
        FOREIGN KEY (animal_id) REFERENCES animals(id)
      )
    ''');
  }
}
