// .x (absorbed from d_rest): `RestResponse`
// represents the HTTP response received. The user
// receives `RestResponse<T>` from the codegen-emitted
// `RestClient` methods.

import 'rest_request.dart';

class RestResponse<T> {
  final int statusCode;
  final String? reasonPhrase;
  final Map<String, String> headers;
  final T? body;
  final String rawBody;
  final RestRequest request;

  const RestResponse({
    required this.statusCode,
    this.reasonPhrase,
    required this.headers,
    this.body,
    required this.rawBody,
    required this.request,
  });

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
  bool get hasBody => body != null;

  @override
  String toString() => 'RestResponse(status=$statusCode, body='
      '${body is String ? body : '<$T>'})';
}
