import 'form_status.dart';
import 'package:d_rocket/d_rocket.dart';

part 'form_enum_request.d_rocket_form.g.dart';

@Form()
class FormEnumRequest {
  FormEnumRequest({required this.status});

  final FormStatus status;
}
