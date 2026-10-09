import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/rest_client_fixture.dart';
import '../support/recording_http_client.dart';

void main() {
  test('generated REST client accepts a per-instance wrapper pipeline',
      () async {
    final List<String> calls = <String>[];
    final RestClientFixture client = createRestClientFixture(
      config: RestClientConfig(
        client: RecordingHttpClient(calls, 'transport'),
        wrappers: <HttpClientWrapper>[
          (HttpClient inner) => RecordingHttpClient(calls, 'outer', inner),
        ],
      ),
    );

    final dynamic response = await client.getEvents();

    expect(response, <String, Object?>{'ok': true});
    expect(calls, <String>['outer', 'transport']);
  });
}
