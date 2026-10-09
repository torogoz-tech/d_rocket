import 'package:d_rocket/d_rocket.dart';

part 'rest_client_fixture.d_rocket_rest_client.g.dart';

@RestClient(baseUrl: 'https://example.test')
abstract class RestClientFixture {
  @HttpGet('/events')
  Future<dynamic> getEvents();
}
