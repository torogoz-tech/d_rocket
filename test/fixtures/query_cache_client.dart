import 'package:d_rocket/d_rocket.dart';

part 'query_cache_client.d_rocket_rest_client.g.dart';

@RestClient(baseUrl: 'https://cache.example')
abstract class QueryCacheClientFixture {
  @QueryCache(tags: <String>['account:{id}'])
  @HttpGet('/accounts/{id}')
  Stream<dynamic> watchAccount(@Path('id') String id);

  @Invalidates(<String>['account:{id}'])
  @HttpPost('/accounts/{id}/refresh')
  Future<dynamic> refreshAccount(@Path('id') String id);
}
