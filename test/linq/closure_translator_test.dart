import 'package:d_rocket/src/linq/closure_translator.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9.8.c — closure_translator', () {
    test('simple equality', () {
      expect(
        translateClosureBody(body: 't.status == 0', paramName: 't'),
        "Expr.binary('==', Expr.member(ParamExpr('t'), 'status'), "
        "Expr.const_(0))",
      );
    });

    test('compound boolean with && and >', () {
      expect(
        translateClosureBody(
          body: 't.status == 0 && t.priority > 5',
          paramName: 't',
        ),
        "Expr.binary('&&', "
        "Expr.binary('==', Expr.member(ParamExpr('t'), 'status'), Expr.const_(0)), "
        "Expr.binary('>', Expr.member(ParamExpr('t'), 'priority'), Expr.const_(5)))",
      );
    });

    test('arithmetic with + and comparison', () {
      expect(
        translateClosureBody(
          body: 't.age + 1 >= 18',
          paramName: 't',
        ),
        "Expr.binary('>=', "
        "Expr.binary('+', Expr.member(ParamExpr('t'), 'age'), Expr.const_(1)), "
        "Expr.const_(18))",
      );
    });

    test('method call (member then paren)', () {
      expect(
        translateClosureBody(
          body: 't.name.toUpperCase()',
          paramName: 't',
        ),
        "Expr.call(Expr.member(ParamExpr('t'), 'name'), 'toUpperCase', "
        "<Expr>[])",
      );
    });

    test('string literal', () {
      expect(
        translateClosureBody(
          body: "t.status == 'active'",
          paramName: 't',
        ),
        contains("Expr.const_('active')"),
      );
    });

    test('boolean literal', () {
      expect(
        translateClosureBody(
          body: 't.done == true',
          paramName: 't',
        ),
        contains("Expr.const_(true)"),
      );
    });

    test('null literal', () {
      expect(
        translateClosureBody(
          body: 't.deletedAt == null',
          paramName: 't',
        ),
        contains('Expr.const_(null)'),
      );
    });

    test('negation (!) and grouping', () {
      expect(
        translateClosureBody(
          body: '!(t.status == 0)',
          paramName: 't',
        ),
        "Expr.unary('!', "
        "Expr.binary('==', Expr.member(ParamExpr('t'), 'status'), Expr.const_(0)))",
      );
    });

    test('multi-method chain', () {
      expect(
        translateClosureBody(
          body: 'a.b.c.d',
          paramName: 't',
        ),
        "Expr.member(Expr.member(Expr.member(Expr.const_(a), 'b'), 'c'), 'd')",
      );
    });
  });

  group('Fase 9.8.d — string interpolation', () {
    test('plain string without interpolation', () {
      expect(
        translateClosureBody(body: "'hello'", paramName: 't'),
        "Expr.const_('hello')",
      );
    });

    test('single \$identifier interpolation', () {
      // "hello \$name" → Expr.binary('+', Expr.const_('hello '), ParamExpr('name'))
      expect(
        translateClosureBody(body: "'hello \$name'", paramName: 'name'),
        contains("ParamExpr('name')"),
      );
      expect(
        translateClosureBody(body: "'hello \$name'", paramName: 'name'),
        contains("Expr.binary('+',"),
      );
    });

    test('multiple interpolations', () {
      final r = translateClosureBody(
        body: "'a \$x b \$y c'",
        paramName: 't',
      );
      // The interpolated names `$x` and `$y` are NOT
      // the lambda param `t`, so they emit as
      // `Expr.const_(x)` / `Expr.const_(y)`.
      expect(r, contains("Expr.const_(x)"));
      expect(r, contains("Expr.const_(y)"));
      // 5 fragments ('a ', x, ' b ', y, ' c') → 4 binary('+') calls.
      expect("Expr.binary('+',".allMatches(r).length, 4);
    });

    test(r'${expr} brace interpolation', () {
      final r = translateClosureBody(
        body: r"'sum: ${t.a + t.b}'",
        paramName: 't',
      );
      // The inner expression `t.a + t.b` should appear.
      expect(r, contains("Expr.member(ParamExpr('t'), 'a')"));
      expect(r, contains("Expr.member(ParamExpr('t'), 'b')"));
      expect(r, contains("Expr.binary('+',"));
    });
  });

  group('Fase 9.8.d — list literal', () {
    test('empty list', () {
      expect(
        translateClosureBody(body: '[]', paramName: 't'),
        'Expr.list(<Expr>[])',
      );
    });

    test('list of integers', () {
      expect(
        translateClosureBody(body: '[1, 2, 3]', paramName: 't'),
        "Expr.list(<Expr>[Expr.const_(1), Expr.const_(2), Expr.const_(3)])",
      );
    });

    test('list of param references', () {
      expect(
        translateClosureBody(body: '[t.a, t.b]', paramName: 't'),
        contains("Expr.member(ParamExpr('t'), 'a')"),
      );
      expect(
        translateClosureBody(body: '[t.a, t.b]', paramName: 't'),
        contains("Expr.member(ParamExpr('t'), 'b')"),
      );
    });
  });

  group('Fase 9.8.e — map / ternary / null-aware', () {
    test('empty map', () {
      expect(
        translateClosureBody(body: '{}', paramName: 't'),
        "Expr.map(<MapEntry<Expr, Expr>>[])",
      );
    });

    test('map with entries', () {
      final r = translateClosureBody(
        body: "{'a': 1, 'b': t.x}",
        paramName: 't',
      );
      expect(r, contains("Expr.map(<MapEntry<Expr, Expr>>["));
      expect(r, contains("MapEntry(Expr.const_('a'), Expr.const_(1))"));
      expect(
          r,
          contains(
              "MapEntry(Expr.const_('b'), Expr.member(ParamExpr('t'), 'x'))"));
    });

    test('ternary', () {
      final r = translateClosureBody(
        body: 't.age >= 18 ? "adult" : "minor"',
        paramName: 't',
      );
      expect(r, contains('Expr.ternary('));
      expect(r, contains("cond: "));
      expect(r, contains("thenBranch: "));
      expect(r, contains("elseBranch: "));
    });

    test(r'null-coalesce (??)', () {
      final r = translateClosureBody(
        body: 't.nickname ?? t.fullName',
        paramName: 't',
      );
      expect(r, contains('Expr.coalesce('));
      expect(r, contains("Expr.member(ParamExpr('t'), 'nickname')"));
      expect(r, contains("Expr.member(ParamExpr('t'), 'fullName')"));
    });

    test(r'null-safe member (?.)', () {
      expect(
        translateClosureBody(body: 't.user?.name', paramName: 't'),
        "Expr.nullSafe(Expr.member(ParamExpr('t'), 'user'), 'name')",
      );
    });
  });
}
