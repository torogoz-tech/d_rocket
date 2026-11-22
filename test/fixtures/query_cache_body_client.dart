import 'package:d_rocket/d_rocket.dart';

import 'transfer_request.dart';

part 'query_cache_body_client.d_rocket_rest_client.g.dart';

@RestClient(baseUrl: 'https://cache.example')
abstract class QueryCacheBodyClientFixture {
  @Invalidates(<String>['account:{request.sourceAccountId}'])
  @HttpPost('/transfers')
  Future<dynamic> execute(@Body() TransferRequest request);
}
