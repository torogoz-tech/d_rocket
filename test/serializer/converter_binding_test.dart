import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/converter_binding_model.dart';

void main() {
  setUp(Serializer.reset);

  test('generated registration installs a class converter binding', () {
    registerConverterBindingModelSerializer();
    final DateTime value = Serializer.fromDynamic<DateTime>(
      '2026-11-22T00:00:00.000Z',
    );

    expect(value, DateTime.parse('2026-11-22T00:00:00.000Z'));
    expect(Serializer.encodeDynamic(value), 'custom:2026-11-22T00:00:00.000Z');
  });
}
