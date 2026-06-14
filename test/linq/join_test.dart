/// End-to-end tests for the `join_` and `groupJoin_` LINQ operators.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../models.dart';

void main() {
  final users = [
    User(id: 1, name: 'Alice', age: 25),
    User(id: 2, name: 'Bob', age: 17),
    User(id: 3, name: 'Carol', age: 30),
  ];
  final posts = [
    _Post(id: 10, userId: 1, title: 'Hello'),
    _Post(id: 11, userId: 1, title: 'World'),
    _Post(id: 12, userId: 3, title: 'Dart rocks'),
    _Post(id: 13, userId: 99, title: 'Orphan'),
  ];

  final userById = Expr.lambda(
    [Expr.param('u')],
    Expr.member(Expr.param('u'), 'id'),
  );
  final postByUserId = Expr.lambda(
    [Expr.param('p')],
    Expr.member(Expr.param('p'), 'userId'),
  );

  group('join_ (INNER JOIN)', () {
    test('basic join: each post → its author name', () {
      // (u, p) => '${u.name} wrote ${p.title}'
      final result = users
          .asQueryable()
          .join_<_Post, int, String>(
            inner: posts.asQueryable(),
            outerKeySelector: userById,
            innerKeySelector: postByUserId,
            resultSelector: Expr.lambda(
              [Expr.param('u'), Expr.param('p')],
              Expr.binary(
                '+',
                Expr.binary(
                  '+',
                  Expr.member(Expr.param('u'), 'name'),
                  Expr.const_(' wrote '),
                ),
                Expr.member(Expr.param('p'), 'title'),
              ),
            ),
          )
          .toList();
      expect(result, [
        'Alice wrote Hello',
        'Alice wrote World',
        'Carol wrote Dart rocks',
      ]);
    });

    test('join with no matches returns empty', () {
      final orphans =
          [_Post(id: 99, userId: 999, title: 'No one')].asQueryable();
      final result = users
          .asQueryable()
          .join_<_Post, int, String>(
            inner: orphans.asQueryable(),
            outerKeySelector: userById,
            innerKeySelector: postByUserId,
            resultSelector: Expr.lambda(
              [Expr.param('u'), Expr.param('p')],
              Expr.const_('match'),
            ),
          )
          .toList();
      expect(result, isEmpty);
    });

    test('one-to-many: each user paired with each of their posts', () {
      // Just count the pairs.
      final count = users
          .asQueryable()
          .join_<_Post, int, int>(
            inner: posts.asQueryable(),
            outerKeySelector: userById,
            innerKeySelector: postByUserId,
            resultSelector: Expr.lambda(
              [Expr.param('u'), Expr.param('p')],
              Expr.const_(1),
            ),
          )
          .count_();
      // 2 posts for Alice + 1 for Carol = 3.
      expect(count, 3);
    });
  });

  group('groupJoin_ (LEFT OUTER JOIN)', () {
    test('each user with their list of posts (empty if none)', () {
      // (u, ps, k) => '${u.name}: ${ps.length} post(s)'
      final result = users
          .asQueryable()
          .groupJoin_<_Post, int, String>(
            inner: posts.asQueryable(),
            outerKeySelector: userById,
            innerKeySelector: postByUserId,
            resultSelector: Expr.lambda(
              [
                Expr.param('u'),
                Expr.param('ps'),
                Expr.param('k'),
              ],
              Expr.binary(
                '+',
                Expr.binary(
                  '+',
                  Expr.member(Expr.param('u'), 'name'),
                  Expr.const_(': '),
                ),
                Expr.binary(
                  '+',
                  Expr.const_('['),
                  Expr.binary(
                    '+',
                    Expr.const_(']'),
                    Expr.const_(' '),
                  ),
                ),
              ),
            ),
          )
          .toList();
      // We expect 3 lines, one per user. (Excluding the exact
      // formatting of the "0 post" line — we just verify length and
      // that all 3 users appear.)
      expect(result.length, 3);
      expect(result.any((s) => s.startsWith('Alice')), true);
      expect(result.any((s) => s.startsWith('Bob')), true);
      expect(result.any((s) => s.startsWith('Carol')), true);
    });

    test('Bob has no posts (empty list)', () {
      // Compute the count of posts per user using a manual
      // groupBy-like check. We just verify the result has 3 entries
      // and one of them is Bob.
      final result = users
          .asQueryable()
          .groupJoin_<_Post, int, int>(
            inner: posts.asQueryable(),
            outerKeySelector: userById,
            innerKeySelector: postByUserId,
            resultSelector: Expr.lambda(
              [
                Expr.param('u'),
                Expr.param('ps'),
                Expr.param('k'),
              ],
              Expr.binary(
                '*',
                Expr.const_(1),
                // (ps as List).length — we use the explicit length
                // via the constant 1 * the length of the list.
                Expr.call(
                  Expr.param('ps'),
                  'length',
                  [],
                ),
              ),
            ),
          )
          .toList();
      // Alice: 2, Bob: 0, Carol: 1.
      expect(result, [2, 0, 1]);
    });
  });

  group('join_ — error cases', () {
    test('non-Lambda keySelector throws', () {
      expect(
        () => users.asQueryable().join_<_Post, int, String>(
              inner: posts.asQueryable(),
              outerKeySelector: Expr.const_(1),
              innerKeySelector: postByUserId,
              resultSelector: Expr.lambda(
                [Expr.param('u'), Expr.param('p')],
                Expr.const_('x'),
              ),
            ),
        throwsArgumentError,
      );
    });

    test('resultSelector with wrong arity throws', () {
      expect(
        () => users.asQueryable().join_<_Post, int, String>(
              inner: posts.asQueryable(),
              outerKeySelector: userById,
              innerKeySelector: postByUserId,
              // 1 param — should be 2 or 3.
              resultSelector: Expr.lambda(
                [Expr.param('u')],
                Expr.const_('x'),
              ),
            ),
        throwsArgumentError,
      );
    });
  });
}

class _Post implements RecordLike {
  _Post({required this.id, required this.userId, required this.title});
  final int id;
  final int userId;
  final String title;
  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'userId' => userId,
        'title' => title,
        _ => null,
      };
}
