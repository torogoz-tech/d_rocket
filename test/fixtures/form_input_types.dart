import 'package:d_rocket/d_rocket.dart';

part 'form_input_types.d_rocket_form.g.dart';

@Form()
class FormInputTypes {
  FormInputTypes(
      {required this.amount, required this.active, required this.date});

  @FormField(input: FormInput.number)
  final int amount;

  @FormField(input: FormInput.boolean)
  final bool active;

  @FormField(input: FormInput.date)
  final DateTime date;
}
