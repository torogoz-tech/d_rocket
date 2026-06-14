import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

class _Order {
  _Order(this.id, this.customerId);
  final int id;
  final int customerId;
}

class _Customer {
  _Customer(this.id, this.name);
  final int id;
  final String name;
}

void main() {
  group('Fase 9.9.b — NavigationRegistry', () {
    test('get returns null for an unpopulated entity', () {
      final order = _Order(1, 100);
      expect(NavigationRegistry.get<_Customer>(order, 'customer'), isNull);
    });

    test('set then get returns the populated value', () {
      final order = _Order(1, 100);
      final customer = _Customer(100, 'John');
      NavigationRegistry.set<_Customer>(order, 'customer', customer);
      expect(
          NavigationRegistry.get<_Customer>(order, 'customer'), same(customer));
    });

    test('set with null stores a "not-found" state (has returns true)', () {
      final order = _Order(1, 100);
      NavigationRegistry.set<_Customer>(order, 'customer', null);
      expect(NavigationRegistry.get<_Customer>(order, 'customer'), isNull);
      expect(NavigationRegistry.has(order, 'customer'), isTrue);
    });

    test('clear removes all navigations for an entity', () {
      final order = _Order(1, 100);
      NavigationRegistry.set<_Customer>(order, 'customer', _Customer(100, 'J'));
      NavigationRegistry.set<_Customer>(order, 'reviewer', _Customer(101, 'R'));
      NavigationRegistry.clear(order);
      expect(NavigationRegistry.has(order, 'customer'), isFalse);
      expect(NavigationRegistry.has(order, 'reviewer'), isFalse);
    });

    test('navigations are per-instance (Expando identity)', () {
      final order1 = _Order(1, 100);
      final order2 = _Order(2, 200);
      NavigationRegistry.set<_Customer>(
          order1, 'customer', _Customer(100, 'A'));
      // order2's nav slot is independent.
      expect(NavigationRegistry.get<_Customer>(order2, 'customer'), isNull);
      expect(NavigationRegistry.get<_Customer>(order1, 'customer'), isNotNull);
    });

    test('all() returns the populated map', () {
      final order = _Order(1, 100);
      final customer = _Customer(100, 'John');
      NavigationRegistry.set<_Customer>(order, 'customer', customer);
      final all = NavigationRegistry.all(order);
      expect(all['customer'], same(customer));
    });

    test('setAll bulk-populates multiple navigations', () {
      final order = _Order(1, 100);
      final customer = _Customer(100, 'John');
      final reviewer = _Customer(200, 'Maria');
      NavigationRegistry.setAll(order, <String, Object?>{
        'customer': customer,
        'reviewer': reviewer,
      });
      expect(
          NavigationRegistry.get<_Customer>(order, 'customer'), same(customer));
      expect(
          NavigationRegistry.get<_Customer>(order, 'reviewer'), same(reviewer));
    });
  });
}
