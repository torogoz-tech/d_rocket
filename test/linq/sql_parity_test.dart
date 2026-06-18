// Phase 3.5.4d.1 — SQL parity tests at the
// translator level.
//
// The SqlTranslator in d_rocket core walks
// an Expr tree and produces a SqlFragment.
// The translator is engine-AGNOSTIC: it
// takes a [SqlDialect] parameter that
// controls 3 dialect-specific bits:
//
//   * stringContainsFunction (INSTR vs
//     STRPOS for String.contains)
//   * jsonObjectFunction (json_object
//     vs jsonb_build_object for map
//     literals)
//   * placeholder (informational only in
//     2.0.0; the provider rewrites `?` to
//     `$1, $2, ...` on the wire)
//
// This test verifies that for every Expr
// shape, the same Expr tree produces the
// SAME SqlFragment on both dialects —
// modulo the 2 real dialect differences
// (STRPOS + jsonb). The 3rd difference
// (placeholder) is at the provider level
// and is tested separately in
// d_rocket_engine_postgres.
//
// What this test proves:
//   1. The translator is engine-agnostic
//      (it doesn't hardcode SQLite or
//      Postgres syntax).
//   2. The same LINQ expression produces
//      the same SQL structure on both
//      engines (so the LINQ -> SQL
//      translation is portable).
//   3. The 2 dialect differences are
//      exactly the 2 we expect (and no
//      more — i.e. the dialect doesn't
//      leak into other parts of the SQL).
//
// What this test does NOT prove:
//   - The runtime behavior matches
//     (gated on TEST_PG_URL; lives in
//     d_rocket_engine_postgres).
//   - The placeholder rewriting works
//     (lives in d_rocket_engine_postgres).

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

/// A test-only Postgres-like dialect. This
/// is exactly what `PostgresDialect` does
/// in the engine package, but inlined here
/// to avoid a circular dependency
/// (d_rocket can't import
/// d_rocket_engine_postgres).
class _PostgresLikeDialect extends SqlDialect {
  const _PostgresLikeDialect();

  @override
  String stringContainsFunction() => 'STRPOS';

  @override
  String jsonObjectFunction() => 'jsonb_build_object';
}

void main() {
  // The translator is constructed with
  // each dialect in turn. The same Expr
  // trees are run through both.
  final defaultTranslator = SqlTranslator(dialect: const DefaultDialect());
  final postgresTranslator =
      SqlTranslator(dialect: const _PostgresLikeDialect());

  group('Parity: trivial (no dialect-dependent syntax)', () {
    test('Const: emits `?` on both dialects', () {
      final defaultFrag = Expr.const_(42).accept(defaultTranslator);
      final postgresFrag = Expr.const_(42).accept(postgresTranslator);
      expect(defaultFrag.sql, '?');
      expect(postgresFrag.sql, '?',
          reason: 'placeholder is `?` on both dialects; provider rewrites');
      expect(defaultFrag.binds, [42]);
      expect(postgresFrag.binds, [42]);
    });

    test('Param: emits the alias on both dialects', () {
      final defaultFrag = Expr.param('u').accept(defaultTranslator);
      final postgresFrag = Expr.param('u').accept(postgresTranslator);
      expect(defaultFrag.sql, 'u');
      expect(postgresFrag.sql, 'u');
      expect(defaultFrag.binds, isEmpty);
      expect(postgresFrag.binds, isEmpty);
    });

    test('Null: emits `NULL` on both dialects (no bind)', () {
      final defaultFrag = Expr.null_.accept(defaultTranslator);
      final postgresFrag = Expr.null_.accept(postgresTranslator);
      expect(defaultFrag.sql, 'NULL');
      expect(postgresFrag.sql, 'NULL');
      expect(defaultFrag.binds, isEmpty);
      expect(postgresFrag.binds, isEmpty);
    });

    test('Const(null): emits `NULL` on both dialects', () {
      // ConstExpr(null) is semantically
      // the same as NullExpr for SQL
      // emission (both → NULL).
      final defaultFrag = Expr.const_(null).accept(defaultTranslator);
      final postgresFrag = Expr.const_(null).accept(postgresTranslator);
      expect(defaultFrag.sql, 'NULL');
      expect(postgresFrag.sql, 'NULL');
    });

    test('Member on alias: emits the column name on both dialects', () {
      // The 2.0.0 translator emits just
      // the column name (no `u.` prefix)
      // for member access on the table
      // alias. This is intentional — see
      // the comment in `visitMemberAccess`.
      final defaultFrag =
          Expr.member(Expr.param('u'), 'id').accept(defaultTranslator);
      final postgresFrag =
          Expr.member(Expr.param('u'), 'id').accept(postgresTranslator);
      expect(defaultFrag.sql, 'id');
      expect(postgresFrag.sql, 'id');
    });

    test('Binary ==: emits `(col = ?)` on both dialects', () {
      final defaultFrag = Expr.binary(
        '==',
        Expr.member(Expr.param('u'), 'id'),
        Expr.const_(5),
      ).accept(defaultTranslator);
      final postgresFrag = Expr.binary(
        '==',
        Expr.member(Expr.param('u'), 'id'),
        Expr.const_(5),
      ).accept(postgresTranslator);
      expect(defaultFrag.sql, '(id = ?)');
      expect(postgresFrag.sql, '(id = ?)');
      expect(defaultFrag.binds, [5]);
      expect(postgresFrag.binds, [5]);
    });

    test('Binary ==: `!=` maps to `<>` (SQL-portable)', () {
      // The 2.0.0 translator maps `!=` to
      // `<>` for SQL-portability (SQLite
      // also accepts `!=` but `<>` is the
      // standard). This is the same on
      // both dialects.
      final defaultFrag = Expr.binary(
        '!=',
        Expr.member(Expr.param('u'), 'id'),
        Expr.const_(5),
      ).accept(defaultTranslator);
      final postgresFrag = Expr.binary(
        '!=',
        Expr.member(Expr.param('u'), 'id'),
        Expr.const_(5),
      ).accept(postgresTranslator);
      expect(defaultFrag.sql, '(id <> ?)');
      expect(postgresFrag.sql, '(id <> ?)');
    });

    test('Binary >=: emits `(col >= ?)` on both dialects', () {
      final defaultFrag = Expr.binary(
        '>=',
        Expr.member(Expr.param('u'), 'age'),
        Expr.const_(18),
      ).accept(defaultTranslator);
      final postgresFrag = Expr.binary(
        '>=',
        Expr.member(Expr.param('u'), 'age'),
        Expr.const_(18),
      ).accept(postgresTranslator);
      expect(defaultFrag.sql, '(age >= ?)');
      expect(postgresFrag.sql, '(age >= ?)');
      expect(defaultFrag.binds, [18]);
    });

    test('Binary + (arithmetic): emits `(col + ?)` on both dialects', () {
      final defaultFrag = Expr.binary(
        '+',
        Expr.member(Expr.param('u'), 'age'),
        Expr.const_(1),
      ).accept(defaultTranslator);
      final postgresFrag = Expr.binary(
        '+',
        Expr.member(Expr.param('u'), 'age'),
        Expr.const_(1),
      ).accept(postgresTranslator);
      expect(defaultFrag.sql, '(age + ?)');
      expect(postgresFrag.sql, '(age + ?)');
    });

    test('Binary && (AND): emits `((A AND B))` on both dialects', () {
      final expr = Expr.binary(
        '&&',
        Expr.binary('>=', Expr.member(Expr.param('u'), 'age'),
            Expr.const_(18)),
        Expr.binary('==', Expr.member(Expr.param('u'), 'active'),
            Expr.const_(true)),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, '((age >= ?) AND (active = ?))');
      expect(postgresFrag.sql, '((age >= ?) AND (active = ?))');
      expect(defaultFrag.binds, [18, true]);
      expect(postgresFrag.binds, [18, true]);
    });

    test('Binary || (OR): emits `((A OR B))` on both dialects', () {
      final expr = Expr.binary(
        '||',
        Expr.binary('==', Expr.member(Expr.param('u'), 'role'),
            Expr.const_('admin')),
        Expr.binary('==', Expr.member(Expr.param('u'), 'role'),
            Expr.const_('owner')),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, "((role = ?) OR (role = ?))");
      expect(postgresFrag.sql, "((role = ?) OR (role = ?))");
      expect(defaultFrag.binds, ['admin', 'owner']);
    });

    test('Unary !: emits `NOT (...)` on both dialects', () {
      final expr = Expr.unary('!', Expr.member(Expr.param('u'), 'active'));
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, 'NOT (active)');
      expect(postgresFrag.sql, 'NOT (active)');
    });

    test('Null check: emits `(col = NULL)` on both dialects', () {
      // The 2.0.0 translator doesn't have
      // special IS NULL handling — it
      // emits `= NULL` (which evaluates
      // to UNKNOWN in SQL, never TRUE).
      // The user code uses
      // `Expr.const_(null)` for the null
      // literal. The runtime behavior
      // matches: the query returns no
      // rows, which is the correct
      // semantics for `x = NULL`.
      final expr = Expr.binary(
        '==',
        Expr.member(Expr.param('u'), 'deleted_at'),
        Expr.null_,
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, '(deleted_at = NULL)');
      expect(postgresFrag.sql, '(deleted_at = NULL)');
    });

    test('Lambda: emits the body on both dialects', () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary('>=', Expr.member(Expr.param('u'), 'age'),
            Expr.const_(18)),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      // The Lambda is unwrapped to the body.
      expect(defaultFrag.sql, '(age >= ?)');
      expect(postgresFrag.sql, '(age >= ?)');
    });
  });

  group('Parity: dialect-dependent syntax (the 2 real differences)', () {
    test('String.contains: INSTR (default) vs STRPOS (Postgres)', () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.call(
          Expr.member(Expr.param('u'), 'name'),
          'contains',
          [Expr.const_('alice')],
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);

      // Default: (INSTR(name, ?) > ?)
      // The 2.0.0 translator wraps the
      // contains check in a `> 0` (the
      // `?` is `0`).
      expect(defaultFrag.sql, '(INSTR(name, ?) > ?)');
      expect(defaultFrag.binds, ['alice', 0]);

      // Postgres: (STRPOS(name, ?) > ?)
      expect(postgresFrag.sql, '(STRPOS(name, ?) > ?)');
      expect(postgresFrag.binds, ['alice', 0]);
    });

    test('String.contains in a WHERE: only the function name differs', () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '&&',
          Expr.call(
            Expr.member(Expr.param('u'), 'name'),
            'contains',
            [Expr.const_('alice')],
          ),
          Expr.member(Expr.param('u'), 'active'),
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql,
          '((INSTR(name, ?) > ?) AND active)');
      expect(postgresFrag.sql,
          '((STRPOS(name, ?) > ?) AND active)');
    });

    test('Map literal: json_object (default) vs jsonb_build_object (Postgres)',
        () {
      final expr = Expr.map([
        MapEntry(Expr.const_('a'), Expr.const_(1)),
        MapEntry(Expr.const_('b'), Expr.const_(2)),
      ]);
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);

      // Default: json_object(?, ?, ?, ?)
      expect(defaultFrag.sql, 'json_object(?, ?, ?, ?)');
      expect(defaultFrag.binds, ['a', 1, 'b', 2]);

      // Postgres: jsonb_build_object(?, ?, ?, ?)
      expect(postgresFrag.sql, 'jsonb_build_object(?, ?, ?, ?)');
      expect(postgresFrag.binds, ['a', 1, 'b', 2]);
    });

    test('Empty Map literal: only the function name differs', () {
      final expr = Expr.map([]);
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, 'json_object()');
      expect(postgresFrag.sql, 'jsonb_build_object()');
    });

    test('Single-entry Map literal: only the function name differs', () {
      final expr = Expr.map([
        MapEntry(Expr.const_('k'), Expr.const_('v')),
      ]);
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, 'json_object(?, ?)');
      expect(postgresFrag.sql, 'jsonb_build_object(?, ?)');
      expect(defaultFrag.binds, ['k', 'v']);
      expect(postgresFrag.binds, ['k', 'v']);
    });
  });

  group('Parity: complex queries (multi-clause WHERE)', () {
    test('Three-clause AND: same SQL on both dialects', () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '&&',
          Expr.binary(
            '&&',
            Expr.binary('>=',
                Expr.member(Expr.param('u'), 'age'), Expr.const_(18)),
            Expr.member(Expr.param('u'), 'active'),
          ),
          Expr.binary('==',
              Expr.member(Expr.param('u'), 'role'), Expr.const_('admin')),
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql,
          '(((age >= ?) AND active) AND (role = ?))');
      expect(postgresFrag.sql,
          '(((age >= ?) AND active) AND (role = ?))');
      expect(defaultFrag.binds, [18, 'admin']);
    });

    test('Nested arithmetic: same SQL on both dialects', () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '>',
          Expr.binary(
            '*',
            Expr.binary('+',
                Expr.member(Expr.param('u'), 'age'), Expr.const_(1)),
            Expr.const_(2),
          ),
          Expr.const_(30),
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, '(((age + ?) * ?) > ?)');
      expect(postgresFrag.sql, '(((age + ?) * ?) > ?)');
      expect(defaultFrag.binds, [1, 2, 30]);
    });

    test('Mixed String.contains + arithmetic: only the INSTR/STRPOS part differs',
        () {
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '&&',
          Expr.call(
            Expr.member(Expr.param('u'), 'name'),
            'contains',
            [Expr.const_('a')],
          ),
          Expr.binary(
            '>=',
            Expr.binary('+',
                Expr.member(Expr.param('u'), 'age'), Expr.const_(1)),
            Expr.const_(18),
          ),
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql,
          '((INSTR(name, ?) > ?) AND ((age + ?) >= ?))');
      expect(postgresFrag.sql,
          '((STRPOS(name, ?) > ?) AND ((age + ?) >= ?))');
      expect(defaultFrag.binds, ['a', 0, 1, 18]);
      expect(postgresFrag.binds, ['a', 0, 1, 18]);
    });
  });

  group('Parity: List literal (IN clause)', () {
    test('List literal: same SQL on both dialects', () {
      final expr = Expr.list([
        Expr.const_(1),
        Expr.const_(2),
        Expr.const_(3),
      ]);
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, '(?, ?, ?)');
      expect(postgresFrag.sql, '(?, ?, ?)');
      expect(defaultFrag.binds, [1, 2, 3]);
    });
  });

  group('Parity: round-trip (same dialect, same input, same output)', () {
    test('Idempotency: translating twice gives the same SqlFragment', () {
      final expr = Expr.binary(
        '>=',
        Expr.member(Expr.param('u'), 'age'),
        Expr.const_(18),
      );
      final frag1 = expr.accept(defaultTranslator);
      final frag2 = expr.accept(defaultTranslator);
      expect(frag1.sql, frag2.sql);
      expect(frag1.binds, frag2.binds);
    });
  });

  group('Parity: summary of dialect differences', () {
    // The whole point of this test file
    // is to verify the 2-difference
    // contract. This test makes it
    // explicit: for any Expr tree that
    // does NOT use String.contains or
    // a map literal, the output is
    // byte-identical between the two
    // dialects.
    test('Pure-comparison queries: byte-identical SQL', () {
      // (u) => u.age >= 18 && u.active
      final expr = Expr.lambda(
        [Expr.param('u')],
        Expr.binary(
          '&&',
          Expr.binary('>=',
              Expr.member(Expr.param('u'), 'age'), Expr.const_(18)),
          Expr.member(Expr.param('u'), 'active'),
        ),
      );
      final defaultFrag = expr.accept(defaultTranslator);
      final postgresFrag = expr.accept(postgresTranslator);
      expect(defaultFrag.sql, postgresFrag.sql,
          reason: 'no dialect-specific syntax, SQL must match');
      expect(defaultFrag.binds, postgresFrag.binds,
          reason: 'binds must be identical');
    });
  });
}
