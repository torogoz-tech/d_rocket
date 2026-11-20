import 'package:test/test.dart';

import '../fixtures/pattern_request.dart';

void main() {
  test('generated Pattern preserves dollar anchors', () {
    final PatternRequestForm form = PatternRequestForm();

    form.code.bind()('12345');
    expect(form.validate(), isTrue);

    form.code.bind()('abc');
    expect(form.validate(), isFalse);
    expect(form.code.errorCode, 'pattern.invalid');
  });
}
