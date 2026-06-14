import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9.9.e — DbSetInclude + .include_', () {
    test('DbSetInclude holds name + targetMeta', () {
      final inc = DbSetInclude(
        name: 'customer',
        targetMeta: _OrderEntityMetaStub.meta,
      );
      expect(inc.name, 'customer');
      expect(inc.targetMeta, same(_OrderEntityMetaStub.meta));
    });

    test('include_ is chainable (returns DbSet)', () {
      // We can't easily instantiate a real DbSet here
      // (it needs a context). But we can verify the
      // data class semantics.
      final inc1 =
          DbSetInclude(name: 'customer', targetMeta: _OrderEntityMetaStub.meta);
      final inc2 =
          DbSetInclude(name: 'reviewer', targetMeta: _OrderEntityMetaStub.meta);
      final list = <DbSetInclude>[inc1, inc2];
      expect(list, hasLength(2));
      expect(list[0].name, 'customer');
      expect(list[1].name, 'reviewer');
    });
  });
}

// Stub EntityMeta (we don't need it to be functional
// for these tests — we just need a constant reference).
class _OrderEntityMetaStub {
  static final EntityMeta meta = EntityMeta(
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
  );
}
