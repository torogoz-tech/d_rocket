import 'login_request.dart';
import 'package:d_rocket/d_rocket.dart';

part 'auth_client_fixture.d_rocket_rest_client.g.dart';

@RestClient(baseUrl: 'https://example.test')
abstract class AuthClientFixture {
  @HttpPost('/auth/login')
  Future<dynamic> login(@Body() LoginRequest request);
}
