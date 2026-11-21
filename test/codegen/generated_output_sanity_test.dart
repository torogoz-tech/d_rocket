import 'package:d_rocket/src/codegen/generated_output_validator.dart';
import 'package:test/test.dart';

void main() {
  test('detects known invalid generated type and template tokens', () {
    final List<String> violations = GeneratedOutputValidator.findViolations(
      r'''final String?? value;
return null as DateTime;
decode<$typeParamName>(json['$jsonKey']);
final values = <dynamic>[];''',
    );

    expect(violations, contains('double-nullable type'));
    expect(violations, contains('nullable DateTime cast'));
    expect(violations, contains('unexpanded template token'));
    expect(violations, contains('dynamic default list'));
  });
}
