import 'package:d_rocket/d_rocket.dart';

part 'login_request.d_rocket_form.g.dart';
part 'login_request.d_rocket_serializer.g.dart';

@Serializable()
@Form()
class LoginRequest {
  LoginRequest({required this.email, required this.password});

  @FormField(label: 'Correo electrónico', order: 1, input: FormInput.email)
  @Required(message: 'El correo es obligatorio')
  @Email(message: 'Ingresa un correo válido')
  final String email;

  @FormField(label: 'Contraseña', order: 2, input: FormInput.password)
  @Required(message: 'La contraseña es obligatoria')
  @Length(min: 8, message: 'La contraseña debe tener al menos 8 caracteres')
  final String password;
}
