import 'package:d_rocket/d_rocket.dart';

part 'pattern_request.d_rocket_form.g.dart';

@Form()
class PatternRequest {
  PatternRequest({required this.code});

  @Pattern(expression: r'^\d+$')
  final String code;
}
