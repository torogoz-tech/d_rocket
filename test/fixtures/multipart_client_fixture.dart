import 'package:d_rocket/d_rocket.dart';

part 'multipart_client_fixture.d_rocket_rest_client.g.dart';

@RestClient(baseUrl: 'https://upload.example')
abstract class MultipartClientFixture {
  @HttpPost('/files')
  Future<dynamic> upload(
    @Part('file') List<int> file,
    @Part('name') String name,
  );
}
