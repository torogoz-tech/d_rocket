import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9.9.a — NavigationMeta', () {
    test('creates a 1:1 navigation', () {
      const nav = NavigationMeta(
        name: 'customer',
        fkColumn: 'customerId',
        targetTable: 'customers',
        targetColumn: 'id',
        targetDartType: dynamic,
      );
      expect(nav.name, 'customer');
      expect(nav.fkColumn, 'customerId');
      expect(nav.targetTable, 'customers');
      expect(nav.targetColumn, 'id');
      expect(nav.isCollection, isFalse);
      expect(nav.reverseFkColumn, isNull);
    });

    test('creates a 1:many navigation', () {
      const nav = NavigationMeta(
        name: 'lineItems',
        fkColumn: 'orderId',
        targetTable: 'line_items',
        targetColumn: 'id',
        targetDartType: dynamic,
        isCollection: true,
        reverseFkColumn: 'orderId',
      );
      expect(nav.isCollection, isTrue);
      expect(nav.reverseFkColumn, 'orderId');
    });

    test('EntityMeta accepts a navigations list', () {
      const navs = <NavigationMeta>[
        NavigationMeta(
          name: 'customer',
          fkColumn: 'customerId',
          targetTable: 'customers',
          targetColumn: 'id',
          targetDartType: dynamic,
        ),
      ];
      final meta = EntityMeta(
        tableName: 'orders',
        columns: const <ColumnMeta>[],
        insertableColumns: const <ColumnMeta>[],
        updatableColumns: const <ColumnMeta>[],
        primaryKey: const ColumnMeta(
          sqlName: 'id',
          dartField: 'id',
          dartType: int,
          isPrimaryKey: true,
        ),
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
        navigations: navs,
      );
      expect(meta.navigations, hasLength(1));
      expect(meta.navigations.first.name, 'customer');
    });

    test('EntityMeta defaults to empty navigations', () {
      final meta = EntityMeta(
        tableName: 'tags',
        columns: const <ColumnMeta>[],
        insertableColumns: const <ColumnMeta>[],
        updatableColumns: const <ColumnMeta>[],
        primaryKey: const ColumnMeta(
          sqlName: 'id',
          dartField: 'id',
          dartType: int,
          isPrimaryKey: true,
        ),
        primaryKeyIndex: 0,
        pkOf: (Object e) => 0,
      );
      expect(meta.navigations, isEmpty);
    });
  });
}
