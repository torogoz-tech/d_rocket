import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../support/recording_http_client.dart';

void main() {
  test('RestClientConfig preserves the documented wrapper order', () async {
    final List<String> calls = <String>[];
    final HttpClient base = RecordingHttpClient(calls, 'transport');
    final RestClientConfig config = RestClientConfig(
      client: base,
      wrappers: <HttpClientWrapper>[
        (HttpClient inner) => RecordingHttpClient(calls, 'outer', inner),
        (HttpClient inner) => RecordingHttpClient(calls, 'inner', inner),
      ],
    );

    final HttpClient pipeline = config.build(
      RecordingHttpClient(calls, 'fallback'),
    );
    await pipeline.execute(
      const RestRequest(method: 'GET', path: '/events'),
      decoder: (dynamic value) => value,
    );

    expect(calls, <String>['outer', 'inner', 'transport']);
  });

  test('empty configuration preserves the supplied fallback', () {
    final RestClientConfig config = const RestClientConfig();
    final HttpClient fallback = RecordingHttpClient(<String>[], 'fallback');
    expect(config.build(fallback), same(fallback));
  });
}
