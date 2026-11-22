import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/query_cache_client.dart';
import '../fixtures/query_cache_body_client.dart';
import '../fixtures/transfer_request.dart';

class _CacheHttpClient implements HttpClient {
  int calls = 0;
  final List<Object?> accountResponses = <Object?>[
    <String, Object?>{'id': '42', 'balance': 100},
    <String, Object?>{'id': '42', 'balance': 125},
  ];

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    calls++;
    final Object? body = request.method == 'GET'
        ? accountResponses.removeAt(0)
        : <String, Object?>{'ok': true};
    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{},
      body: body,
      rawBody: '',
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}

void main() {
  test('generated query cache deduplicates and invalidates active streams',
      () async {
    final _CacheHttpClient transport = _CacheHttpClient();
    final QueryCacheClientFixture client = createQueryCacheClientFixture(
      config: RestClientConfig(client: transport),
    );
    final List<Object?> first = <Object?>[];
    final List<Object?> second = <Object?>[];
    final StreamSubscription<Object?> firstSubscription =
        client.watchAccount('42').listen(first.add);
    final StreamSubscription<Object?> secondSubscription =
        client.watchAccount('42').listen(second.add);

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 1);
    expect(first.single, <String, Object?>{'id': '42', 'balance': 100});
    expect(second.single, <String, Object?>{'id': '42', 'balance': 100});

    await client.refreshAccount('42');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(transport.calls, 3);
    expect(first.last, <String, Object?>{'id': '42', 'balance': 125});
    expect(second.last, <String, Object?>{'id': '42', 'balance': 125});

    await firstSubscription.cancel();
    await secondSubscription.cancel();
    await dRest.clearQueryCache();
  });

  test('generated invalidation resolves properties from body parameters',
      () async {
    final _CacheHttpClient transport = _CacheHttpClient();
    registerTransferRequestSerializer();
    final QueryCacheClientFixture queryClient = createQueryCacheClientFixture(
      config: RestClientConfig(client: transport),
    );
    final QueryCacheBodyClientFixture client =
        createQueryCacheBodyClientFixture(
      config: RestClientConfig(client: transport),
    );

    final List<Object?> values = <Object?>[];
    final StreamSubscription<Object?> subscription =
        queryClient.watchAccount('42').listen(values.add);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    await client.execute(const TransferRequest(sourceAccountId: '42'));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(transport.calls, 3);
    expect(values.last, <String, Object?>{'id': '42', 'balance': 125});
    await subscription.cancel();
    await dRest.clearQueryCache();
  });

  test('generated clients can use an instance-scoped query cache', () async {
    final _CacheHttpClient transport = _CacheHttpClient();
    final RestQueryCache customCache = RestQueryCache();
    final QueryCacheClientFixture client = createQueryCacheClientFixture(
      config: RestClientConfig(client: transport, queryCache: customCache),
    );
    final StreamSubscription<Object?> subscription =
        client.watchAccount('42').listen((Object? _) {});

    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(customCache.entryCount, 1);
    expect(dRest.queryCache.entryCount, 0);
    await subscription.cancel();
    await customCache.clear();
  });
}
