// Tests for the selectMany_ LINQ operator (commit:
// feat(linq): add selectMany_ operator).
//
// selectMany_ is the LINQ equivalent of flatMap.
// It takes a single-parameter selector that returns
// an Iterable, projects each element to its inner
// collection, and flattens the result. With the
// optional resultSelector, each (outer, inner) pair
// is mapped to a final result.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

class Order implements RecordLike {
  Order(this.id, this.items);
  final int id;
  final List<LineItem> items;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'items' => items,
        _ => null,
      };

  @override
  String toString() => 'Order(id: $id, items: $items)';
}

class LineItem implements RecordLike {
  LineItem(this.sku, this.qty);
  final String sku;
  final int qty;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'sku' => sku,
        'qty' => qty,
        _ => null,
      };

  @override
  String toString() => 'LineItem($sku x$qty)';
}

void main() {
  group('selectMany_', () {
    final List<Order> orders = <Order>[
      Order(1, <LineItem>[
        LineItem('A', 2),
        LineItem('B', 3),
      ]),
      Order(2, <LineItem>[
        LineItem('C', 1),
      ]),
      Order(3, <LineItem>[]),
    ];

    test('flattens the inner collections into a single sequence', () {
      final List<LineItem> all = orders
          .asQueryable()
          .selectMany_<LineItem, LineItem>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.member(Expr.param('o'), 'items'),
            ),
          )
          .toList();
      expect(all, hasLength(3));
      expect(all.map((LineItem l) => l.sku).toList(), <String>['A', 'B', 'C']);
      expect(all.map((LineItem l) => l.qty).toList(), <int>[2, 3, 1]);
    });

    test('skips outers whose inner collection is empty', () {
      final List<LineItem> all = orders
          .asQueryable()
          .selectMany_<LineItem, LineItem>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.member(Expr.param('o'), 'items'),
            ),
          )
          .toList();
      // The third order had an empty list and
      // contributed zero elements.
      expect(all.length, 3);
    });

    test('resultSelector combines outer and inner into a result', () {
      final List<String> summary = orders
          .asQueryable()
          .selectMany_<LineItem, String>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.member(Expr.param('o'), 'items'),
            ),
            resultSelector: Expr.lambda(
              <Expr>[Expr.param('o'), Expr.param('i')],
              Expr.binary(
                '+',
                Expr.binary(
                  '+',
                  Expr.const_('Order '),
                  Expr.member(Expr.param('o'), 'id'),
                ),
                Expr.binary(
                  '+',
                  Expr.const_(': '),
                  Expr.member(Expr.param('i'), 'sku'),
                ),
              ),
            ),
          )
          .toList();
      expect(summary, <String>[
        'Order 1: A',
        'Order 1: B',
        'Order 2: C',
      ]);
    });

    test('rejects non-LambdaExpr collectionSelector', () {
      expect(
        () => orders.asQueryable().selectMany_<LineItem, LineItem>(
              // Expr.const_ is not a LambdaExpr.
              Expr.const_('not a lambda'),
            ),
        throwsArgumentError,
      );
    });

    test('rejects collectionSelector with wrong arity', () {
      expect(
        () => orders.asQueryable().selectMany_<LineItem, LineItem>(
              // 2 params, but the selector must be 1 param.
              Expr.lambda(
                <Expr>[Expr.param('o'), Expr.param('x')],
                Expr.const_('x'),
              ),
            ),
        throwsArgumentError,
      );
    });

    test('rejects resultSelector with wrong arity', () {
      expect(
        () => orders.asQueryable().selectMany_<LineItem, LineItem>(
              Expr.lambda(
                <Expr>[Expr.param('o')],
                Expr.member(Expr.param('o'), 'items'),
              ),
              resultSelector:
                  // 3 params, but the resultSelector must be 2.
                  Expr.lambda(
                <Expr>[
                  Expr.param('o'),
                  Expr.param('i'),
                  Expr.param('k'),
                ],
                Expr.const_('x'),
              ),
            ),
        throwsArgumentError,
      );
    });

    test('throws if collectionSelector returns a non-Iterable', () {
      // The selector returns a String, not an Iterable.
      // The runtime should fail at the first moveNext
      // that needs an inner iterator.
      final IQueryable<String> bad = orders
          .asQueryable()
          .selectMany_<String, String>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.const_('not an iterable'),
            ),
          );
      expect(() => bad.toList(), throwsStateError);
    });

    test('an empty source yields an empty result', () {
      final List<LineItem> all = <Order>[]
          .asQueryable()
          .selectMany_<LineItem, LineItem>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.member(Expr.param('o'), 'items'),
            ),
          )
          .toList();
      expect(all, isEmpty);
    });

    test('lazy evaluation: only iterates up to the first take_', () {
      // selectMany_ is lazy: the resultSelector body is
      // not called for the inner items beyond the
      // first `take_` cap.
      final List<LineItem> first = orders
          .asQueryable()
          .selectMany_<LineItem, LineItem>(
            Expr.lambda(
              <Expr>[Expr.param('o')],
              Expr.member(Expr.param('o'), 'items'),
            ),
          )
          .take_(2)
          .toList();
      expect(first, hasLength(2));
      expect(first[0].sku, 'A');
      expect(first[1].sku, 'B');
    });
  });
}
