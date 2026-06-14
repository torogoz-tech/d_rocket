import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

// Mock entities + EntityMeta for the populator test.
// In production these come from the codegen on
// @Table classes.

class _Customer {
  _Customer(this.id, this.name);
  final int id;
  final String name;
}

class _Order {
  _Order(this.id, this.customerId);
  final int id;
  final int customerId;
}

EntityMeta _makeCustomerMeta() {
  return EntityMeta(
    tableName: 'customers',
    columns: const <ColumnMeta>[
      ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      ),
      ColumnMeta(
        sqlName: 'name',
        dartField: 'name',
        dartType: String,
      ),
    ],
    insertableColumns: const <ColumnMeta>[],
    updatableColumns: const <ColumnMeta>[],
    primaryKey: const ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
    ),
    primaryKeyIndex: 0,
    pkOf: (Object e) => (e as _Customer).id,
    readColumn: (Object e, ColumnMeta c) {
      if (c.dartField == 'id') return (e as _Customer).id;
      if (c.dartField == 'name') return (e as _Customer).name;
      return null;
    },
    fromRow: (Map<String, Object?> r) => _Customer(
      r['id']! as int,
      r['name']! as String,
    ),
  );
}

EntityMeta _makeOrderMeta() {
  return EntityMeta(
    tableName: 'orders',
    columns: const <ColumnMeta>[
      ColumnMeta(
        sqlName: 'id',
        dartField: 'id',
        dartType: int,
        isPrimaryKey: true,
      ),
      ColumnMeta(
        sqlName: 'customer_id',
        dartField: 'customerId',
        dartType: int,
      ),
    ],
    insertableColumns: const <ColumnMeta>[],
    updatableColumns: const <ColumnMeta>[],
    primaryKey: const ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
    ),
    primaryKeyIndex: 0,
    pkOf: (Object e) => (e as _Order).id,
    readColumn: (Object e, ColumnMeta c) {
      if (c.dartField == 'id') return (e as _Order).id;
      if (c.dartField == 'customerId') return (e as _Order).customerId;
      return null;
    },
    navigations: const <NavigationMeta>[
      NavigationMeta(
        name: 'customer',
        fkColumn: 'customerId',
        targetTable: 'customers',
        targetColumn: 'id',
        targetDartType: _Customer,
      ),
    ],
  );
}

void main() {
  group('Fase 9.9.c — NavigationPopulator', () {
    late EntityMeta orderMeta;
    late EntityMeta customerMeta;

    setUp(() {
      orderMeta = _makeOrderMeta();
      customerMeta = _makeCustomerMeta();
    });

    test('populates the navigation for a list of entities', () async {
      final orders = <_Order>[
        _Order(1, 100),
        _Order(2, 200),
        _Order(3, 100), // shares customer 100 with order 1
      ];

      // The "DB" — just returns the rows the user
      // has in memory (simulating a real SELECT).
      final customers = <_Customer>[
        _Customer(100, 'John'),
        _Customer(200, 'Maria'),
      ];
      final List<Map<String, Object?>> allRows = <Map<String, Object?>>[
        for (final _Customer c in customers)
          <String, Object?>{'id': c.id, 'name': c.name},
      ];

      final related = await NavigationPopulator.populate<_Customer>(
        entities: orders,
        sourceMeta: orderMeta,
        targetMeta: customerMeta,
        navigationName: 'customer',
        selectFn: (String sql, List<Object?> binds) async {
          // Simulate: return all rows (the real DB
          // would filter by `id IN (?, ?)`).
          return allRows;
        },
      );

      expect(related, hasLength(2));
      // Each order should now have its customer
      // populated in the registry.
      expect(NavigationRegistry.get<_Customer>(orders[0], 'customer')?.name,
          'John');
      expect(NavigationRegistry.get<_Customer>(orders[1], 'customer')?.name,
          'Maria');
      expect(NavigationRegistry.get<_Customer>(orders[2], 'customer')?.name,
          'John'); // shared customer
    });

    test('throws when the navigation name is not found', () async {
      final orders = <_Order>[_Order(1, 100)];
      await expectLater(
        NavigationPopulator.populate<_Customer>(
          entities: orders,
          sourceMeta: orderMeta,
          targetMeta: customerMeta,
          navigationName: 'nonexistent',
          selectFn: (String sql, List<Object?> binds) async => <Object?>[],
        ),
        throwsStateError,
      );
    });

    test('returns empty list when source entities are empty', () async {
      final related = await NavigationPopulator.populate<_Customer>(
        entities: <_Order>[],
        sourceMeta: orderMeta,
        targetMeta: customerMeta,
        navigationName: 'customer',
        selectFn: (String sql, List<Object?> binds) async => <Object?>[],
      );
      expect(related, isEmpty);
    });

    test('passes the FK values as binds to the SELECT', () async {
      final orders = <_Order>[
        _Order(1, 100),
        _Order(2, 200),
      ];
      List<Object?>? capturedBinds;
      await NavigationPopulator.populate<_Customer>(
        entities: orders,
        sourceMeta: orderMeta,
        targetMeta: customerMeta,
        navigationName: 'customer',
        selectFn: (String sql, List<Object?> binds) async {
          capturedBinds = binds;
          return <Object?>[];
        },
      );
      expect(capturedBinds, <Object?>[100, 200]);
    });
  });
}
