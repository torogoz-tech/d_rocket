import 'package:d_rocket/d_rocket.dart';

part 'composite_form_request.d_rocket_form.g.dart';

@Form()
class CompositeFormRequest {
  const CompositeFormRequest({
    required this.expiry,
    required this.expiryMonth,
    required this.expiryYear,
  });

  @FormField(
    binding: FormBinding(fields: <String>['expiryMonth', 'expiryYear']),
  )
  final String expiry;

  final String expiryMonth;

  final String expiryYear;
}
