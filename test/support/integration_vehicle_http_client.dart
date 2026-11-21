import 'package:d_rocket/d_rocket.dart';

class IntegrationVehicleHttpClient implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    final Map<String, dynamic> vehicle = <String, dynamic>{
      'id': 'vehicle-1',
      'type': 'truck',
      'plate': 'AB-1A',
      'year': 2024,
    };
    final dynamic body = request.method == 'GET'
        ? <String, dynamic>{
            'data': <dynamic>[vehicle],
            'message': null,
          }
        : <String, dynamic>{
            'data': vehicle,
            'message': null,
          };

    return RestResponse<dynamic>(
      statusCode: 200,
      headers: const <String, String>{'content-type': 'application/json'},
      body: body,
      rawBody: body.toString(),
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}
