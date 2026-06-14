import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9.9.d — NavRef + SQL JOIN', () {
    test('NavRef stores navigation metadata', () {
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      expect(nav.name, 'customer');
      expect(nav.targetTable, 'customers');
      expect(nav.targetAlias, 'c');
      expect(nav.fkColumn, 'customer_id');
      expect(nav.pkColumn, 'id');
    });

    test('SQL translator emits a column ref for NavRef', () {
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      final translator = SqlTranslator();
      final frag = nav.accept(translator);
      expect(frag.sql, 'c.id');
      expect(frag.binds, isEmpty);
    });

    test('SQL translator collects an INNER JOIN for NavRef', () {
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      final translator = SqlTranslator();
      nav.accept(translator);
      final joins = translator.drainCollectedJoins();
      expect(joins, hasLength(1));
      expect(joins.first, contains('INNER JOIN customers c'));
      expect(joins.first, contains('c.id = customer_id'));
    });

    test('Two NavRefs to the same target produce one JOIN (de-dup)', () {
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      final translator = SqlTranslator();
      // The same NavRef referenced twice.
      nav.accept(translator);
      nav.accept(translator);
      final joins = translator.drainCollectedJoins();
      expect(joins, hasLength(1), reason: 'duplicate JOINs should be de-duped');
    });

    test('drainCollectedJoins clears the list', () {
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      final translator = SqlTranslator();
      nav.accept(translator);
      final first = translator.drainCollectedJoins();
      expect(first, hasLength(1));
      final second = translator.drainCollectedJoins();
      expect(second, isEmpty, reason: 'drain should clear the list');
    });

    test('Two NavRefs to different targets produce two JOINs', () {
      const nav1 = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      const nav2 = NavRef(
        name: 'reviewer',
        targetTable: 'reviewers',
        targetAlias: 'r',
        fkColumn: 'reviewer_id',
        pkColumn: 'id',
      );
      final translator = SqlTranslator();
      nav1.accept(translator);
      nav2.accept(translator);
      final joins = translator.drainCollectedJoins();
      expect(joins, hasLength(2));
    });

    test(
        'A nested expr (Binary with NavRef inside MemberAccess) collects the JOIN',
        () {
      // Simulates: o.customer.name == 'John'
      // Tree: binary(==, member(navRef(customer), 'name'), const_('John'))
      const nav = NavRef(
        name: 'customer',
        targetTable: 'customers',
        targetAlias: 'c',
        fkColumn: 'customer_id',
        pkColumn: 'id',
      );
      const tree = BinaryExpr(
        '==',
        MemberAccessExpr(
            NavRef(
                name: 'customer',
                targetTable: 'customers',
                targetAlias: 'c',
                fkColumn: 'customer_id',
                pkColumn: 'id'),
            'name'),
        ConstExpr('John'),
      );
      // ignore: unused_local_variable
      const unused = nav; // documentation reference
      final translator = SqlTranslator();
      tree.accept(translator);
      final joins = translator.drainCollectedJoins();
      expect(joins, hasLength(1));
      expect(joins.first, contains('INNER JOIN customers c'));
    });
  });
}
