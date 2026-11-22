import 'package:d_rocket/d_rocket.dart';
import '../fixtures/value_model.dart';
import 'package:test/test.dart';

void main() {
  test('generated copyWith distinguishes omitted and explicit null', () {
    const ValueModel value = ValueModel(
      id: '1',
      description: 'original',
      labels: <String>['a'],
    );

    expect(value.copyWith(id: '2').description, 'original');
    expect(value.copyWith(description: null).description, isNull);
  });

  test('generated equality uses deep collection comparison', () {
    const ValueModel first = ValueModel(
      id: '1',
      description: null,
      labels: <String>['a', 'b'],
    );
    const ValueModel second = ValueModel(
      id: '1',
      description: null,
      labels: <String>['a', 'b'],
    );

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });
}
