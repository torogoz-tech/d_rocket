import 'package:d_rocket/d_rocket.dart';

part 'form_format_request.d_rocket_form.g.dart';

@Form()
class FormFormatRequest {
  FormFormatRequest({required this.value});

  @Format.trim()
  @Format.lowercase()
  final String value;
}
