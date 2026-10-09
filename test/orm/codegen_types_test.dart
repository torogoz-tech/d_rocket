import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

import '../fixtures/codegen_types.dart';

void main() {
  setUp(() {
    EntityRegistry.reset();
    registerCodegenTypesEntityEntityMeta();
  });

  test('generated serializer preserves nullable and DateTime values', () {
    final CodegenTypesEntity original = CodegenTypesEntity(
      id: 'evt-1',
      name: 'event',
      description: null,
      timestamp: DateTime.utc(2026, 10, 8, 12, 30),
      optionalTimestamp: null,
      amount: 12.5,
    );

    final Map<String, dynamic> json = original.toJson();
    final CodegenTypesEntity restored = CodegenTypesEntityFromJson(json);

    expect(json['description'], isNull);
    expect(json['optionalTimestamp'], isNull);
    expect(json['timestamp'], '2026-10-08T12:30:00.000Z');
    expect(restored.timestamp, original.timestamp);
    expect(restored.description, isNull);
    expect(restored.amount, 12.5);
  });

  test('generated ORM materializes nullable SQLite values', () {
    final EntityMeta meta = EntityRegistry.metaFor(CodegenTypesEntity);
    final CodegenTypesEntity entity = meta.fromRow!(<String, Object?>{
      'id': 'evt-2',
      'name': 'event',
      'description': null,
      'timestamp': '2026-10-08T12:30:00.000Z',
      'optional_timestamp': null,
      'amount': 9,
    }) as CodegenTypesEntity;

    expect(entity.description, isNull);
    expect(entity.optionalTimestamp, isNull);
    expect(entity.timestamp, DateTime.utc(2026, 10, 8, 12, 30));
    expect(entity.amount, 9.0);
    expect(
        meta.readColumn!(
          entity,
          meta.columns.firstWhere(
            (ColumnMeta column) => column.dartField == 'timestamp',
          ),
        ),
        '2026-10-08T12:30:00.000Z');
  });

  test('generated ORM persists DateTime through SQLite text storage', () {
    final SqliteQueryProvider provider = SqliteQueryProvider.inMemory();
    addTearDown(provider.dispose);
    final EntityMeta meta = EntityRegistry.metaFor(CodegenTypesEntity);
    provider.execute(meta.createTableDdl());

    final CodegenTypesEntity entity = CodegenTypesEntity(
      id: 'evt-3',
      name: 'event',
      description: 'stored',
      timestamp: DateTime.utc(2026, 10, 8, 13),
      optionalTimestamp: null,
      amount: 7.25,
    );
    final List<ColumnMeta> columns = meta.columns;
    final List<Object?> values = columns
        .map((ColumnMeta column) => meta.readColumn!(entity, column))
        .toList();
    provider.execute(
      'INSERT INTO ${meta.tableName} '
      '(${columns.map((ColumnMeta column) => column.sqlName).join(', ')}) '
      'VALUES (${List<String>.filled(columns.length, '?').join(', ')})',
      values,
    );

    final dynamic row =
        provider.select('SELECT * FROM ${meta.tableName}').first;
    final CodegenTypesEntity restored = meta.fromRow!(
      Map<String, Object?>.from(row as Map),
    ) as CodegenTypesEntity;
    expect(restored.timestamp, DateTime.utc(2026, 10, 8, 13));
    expect(restored.optionalTimestamp, isNull);
    expect(restored.amount, 7.25);
  });
}
