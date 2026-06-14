import 'package:d_rocket/src/cli/closure_transformer.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 9.8.g — transformFileSource', () {
    test('rewrites single-line where_ closure', () {
      const src = '''
void main() {
  final x = db.set<T>().where_((t) => t.status == 0);
}''';
      final out = transformFileSource(src);
      expect(out, contains("where_(Expr.lambda("));
      expect(out, contains("Expr.binary('=='"));
    });

    test('rewrites orderBy_ closure', () {
      const src = '''
void main() {
  final x = db.set<T>().orderBy_((t) => t.age);
}''';
      final out = transformFileSource(src);
      expect(out, contains("orderBy_(Expr.lambda("));
      expect(out, contains("Expr.member(ParamExpr('t'), 'age')"));
    });

    test('rewrites multiple closures on different lines', () {
      const src = '''
void main() {
  final a = db.set<T>().where_((t) => t.x == 1);
  final b = db.set<T>().where_((t) => t.y == 2);
}''';
      final out = transformFileSource(src);
      expect("where_(Expr.lambda(".allMatches(out).length, 2);
    });

    test('skips non-closure arguments (Expr.lambda already)', () {
      const src = '''
void main() {
  final x = db.set<T>().where_(Expr.lambda(...));
}''';
      final out = transformFileSource(src);
      expect(out, equals(src));
    });
  });
}
