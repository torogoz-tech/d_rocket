import 'dart:async';
import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

class _StreamingHttpClient extends http.BaseClient {
  List<int>? bytes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    bytes = await request.finalize().fold<List<int>>(<int>[], (
      List<int> result,
      List<int> chunk,
    ) {
      result.addAll(chunk);
      return result;
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"ok":true}')),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  test('streams request chunks and reports progress', () async {
    final _StreamingHttpClient transport = _StreamingHttpClient();
    final List<RestTransferProgress> progress = <RestTransferProgress>[];
    final HttpPackageClient client = HttpPackageClient(client: transport);
    final RestResponse<dynamic> response = await client.execute(
      RestRequest(
        method: 'POST',
        baseUrl: 'https://example.test',
        path: '/upload',
        body: RestStreamingBody(
          chunks: Stream<List<int>>.fromIterable(<List<int>>[
            <int>[1, 2],
            <int>[3, 4],
          ]),
          totalBytes: 4,
          onProgress: progress.add,
        ),
      ),
      decoder: (Object? value) => value,
    );

    expect(response.statusCode, 200);
    expect(transport.bytes, <int>[1, 2, 3, 4]);
    expect(progress.last.sentBytes, 4);
    expect(progress.last.uploadFraction, 1);
    await client.close();
  });
}
