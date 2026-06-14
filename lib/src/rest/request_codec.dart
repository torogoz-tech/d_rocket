// .x (absorbed from d_rest): `RequestCodec`
// is the function signature that any `HttpClient`
// implementation must satisfy. It takes a
// `RestRequest` and a `Decoder<dynamic>` (so the
// user can decode the body into any type), and
// returns a `RestResponse<dynamic>`.

import 'decoder.dart';
import 'rest_request.dart';
import 'rest_response.dart';

typedef RequestCodec = Future<RestResponse<dynamic>> Function(
  RestRequest request,
  Decoder<dynamic> decoder,
);
