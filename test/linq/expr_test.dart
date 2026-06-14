/// Unit tests for the public Expr DSL.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  group('Expr.toString', () {
    test('param', () {
      expect(Expr.param('x').toString(), 'x');
    });

    test('const string, int, and null', () {
      expect(Expr.const_('hi').toString(), "'hi'");
      expect(Expr.const_(18).toString(), '18');
      expect(Expr.null_.toString(), 'null');
    });

    test('binary wraps in parens', () {
      final e = Expr.binary('>', Expr.param('x'), Expr.const_(18));
      expect(e.toString(), '(x > 18)');
    });

    test('lambda prints params and body', () {
      final e = Expr.lambda(
        [Expr.param('x')],
        Expr.binary('>', Expr.param('x'), Expr.const_(18)),
      );
      expect(e.toString(), '(x) => (x > 18)');
    });

    test('member access', () {
      final e = Expr.member(Expr.param('x'), 'age');
      expect(e.toString(), 'x.age');
    });

    test('method call with one arg', () {
      final e = Expr.call(Expr.param('x'), 'startsWith', [Expr.const_('A')]);
      expect(e.toString(), "x.startsWith('A')");
    });

    test('nested boolean', () {
      final e = Expr.lambda(
        [Expr.param('x')],
        Expr.binary(
          '||',
          Expr.binary('==', Expr.member(Expr.param('x'), 'id'), Expr.const_(5)),
          Expr.binary('!=', Expr.member(Expr.param('x'), 'email'), Expr.null_),
        ),
      );
      expect(
        e.toString(),
        "(x) => ((x.id == 5) || (x.email != null))",
      );
    });
  });

  group('Expr.eval — primitives', () {
    test('const returns the value', () {
      expect(Expr.const_(42).eval({}), 42);
      expect(Expr.const_('hi').eval({}), 'hi');
      expect(Expr.null_.eval({}), null);
    });

    test('param looks up by name', () {
      expect(Expr.param('x').eval({'x': 7}), 7);
      expect(Expr.param('missing').eval({}), null);
    });

    test('arithmetic', () {
      final e = Expr.binary('+', Expr.const_(2), Expr.const_(3));
      expect(e.eval({}), 5);
    });

    test('comparison', () {
      final e = Expr.binary('>', Expr.const_(5), Expr.const_(3));
      expect(e.eval({}), true);
    });

    test('boolean ops with short-circuit-like semantics', () {
      // Note: '||' and '&&' are evaluated strictly (both sides).
      // Short-circuit is a concern.
      final e = Expr.binary(
        '||',
        Expr.const_(false),
        Expr.const_(true),
      );
      expect(e.eval({}), true);
    });
  });

  group('Expr.eval — the 3 demo expressions (User)', () {
    final alice = User(id: 1, name: 'Alice', age: 25, email: 'a@x.com');
    final bob = User(id: 5, name: 'Bob', age: 17, email: null);
    final carol = User(id: 5, name: 'Carol', age: 30, email: null);
    final dan = User(id: 99, name: 'Dan', age: 40, email: null);

    test('expression 1: x.age > 18', () {
      final e = Expr.lambda(
        [Expr.param('x')],
        Expr.binary('>', Expr.member(Expr.param('x'), 'age'), Expr.const_(18)),
      );
      expect(e.eval({'x': alice}), true);
      expect(e.eval({'x': bob}), false);
    });

    test('expression 2: x.name.startsWith("A")', () {
      final e = Expr.lambda(
        [Expr.param('x')],
        Expr.call(
          Expr.member(Expr.param('x'), 'name'),
          'startsWith',
          [Expr.const_('A')],
        ),
      );
      expect(e.eval({'x': alice}), true);
      expect(e.eval({'x': bob}), false);
    });

    test('expression 3: x.id == 5 || x.email != null', () {
      final e = Expr.lambda(
        [Expr.param('x')],
        Expr.binary(
          '||',
          Expr.binary('==', Expr.member(Expr.param('x'), 'id'), Expr.const_(5)),
          Expr.binary('!=', Expr.member(Expr.param('x'), 'email'), Expr.null_),
        ),
      );
      expect(e.eval({'x': alice}), true); // email != null
      expect(e.eval({'x': bob}), true); // id == 5
      expect(e.eval({'x': carol}), true); // id == 5
      expect(e.eval({'x': dan}), false); // neither
    });
  });

  group('Expr.eval — Map<String, Object?> target', () {
    test('member access on a map', () {
      final row = {'id': 1, 'name': 'Alice', 'age': 25};
      final e = Expr.member(Expr.param('row'), 'age');
      expect(e.eval({'row': row}), 25);
    });

    test('full predicate on a map', () {
      final rows = [
        {'id': 1, 'age': 25},
        {'id': 2, 'age': 17},
        {'id': 3, 'age': 30},
      ];
      final predicate = Expr.lambda(
        [Expr.param('row')],
        Expr.binary(
          '>',
          Expr.member(Expr.param('row'), 'age'),
          Expr.const_(18),
        ),
      );
      final result = rows.where((r) => predicate.eval({'row': r}) == true);
      expect(result.toList(), rows.where((r) => r['age']! > 18).toList());
    });
  });
}
