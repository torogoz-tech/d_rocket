import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('ValueEquality', () {
    test('compares nested JSON-like values deeply', () {
      expect(
        ValueEquality.equals(
          <String, Object?>{
            'id': 1,
            'items': <Object?>[true, <String, Object?>{'name': 'A'}],
          },
          <String, Object?>{
            'items': <Object?>[true, <String, Object?>{'name': 'A'}],
            'id': 1,
          },
        ),
        isTrue,
      );
    });

    test('compares sets without depending on insertion order', () {
      expect(
        ValueEquality.equals(<String>{'a', 'b'}, <String>{'b', 'a'}),
        isTrue,
      );
      expect(ValueEquality.equals(<String>{'a'}, <String>{'b'}), isFalse);
    });

    test('produces equal hashes for equal nested values', () {
      final Object left = <String, Object?>{
        'b': <int>[2, 3],
        'a': 'value',
      };
      final Object right = <String, Object?>{
        'a': 'value',
        'b': <int>[2, 3],
      };
      expect(ValueEquality.hash(left), ValueEquality.hash(right));
    });
  });

  test('Serializable exposes opt-in value model flags', () {
    const Serializable annotation = Serializable(copyWith: true, equality: true);
    expect(annotation.copyWith, isTrue);
    expect(annotation.equality, isTrue);
  });
}
