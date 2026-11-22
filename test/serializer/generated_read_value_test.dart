import 'package:test/test.dart';

import '../fixtures/read_value_model.dart';

void main() {
  test('generated serializer uses JsonKey readValue hook', () {
    final ReadValueModel model = ReadValueModelFromJson(
      <String, dynamic>{'display_name': 'Ada'},
    );

    expect(model.displayName, 'Ada');
    expect(model.toJson(), <String, dynamic>{'displayName': 'Ada'});
  });
}
