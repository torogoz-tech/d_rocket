import '../fixtures/value_model.dart';
import '../fixtures/generic_value_model.dart';
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

  test('generated schema describes fields and required values', () {
    final Map<String, Object?> schema = ValueModelJsonSchema();
    expect(schema['type'], 'object');
    expect(
      (schema['properties']! as Map<String, Object?>).keys,
      containsAll(<String>['id', 'description', 'labels']),
    );
    expect(schema['required'], contains('id'));
    expect(schema['required'], isNot(contains('description')));
  });

  test('generic value helpers preserve type parameters and equality', () {
    const GenericValue<String> value =
        GenericValue<String>(data: 'one', message: 'ok');

    expect(value.copyWith(data: 'two').data, 'two');
    expect(
      value,
      const GenericValue<String>(data: 'one', message: 'ok'),
    );
  });
}
