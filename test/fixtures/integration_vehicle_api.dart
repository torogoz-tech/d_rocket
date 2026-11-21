import 'package:d_rocket/d_rocket.dart';

import 'integration_vehicle_request.dart';

part 'integration_vehicle_api.d_rocket_serializer.g.dart';
part 'integration_vehicle_api.d_rocket_rest_client.g.dart';

@Serializable()
class VehicleResponse {
  const VehicleResponse({
    required this.id,
    required this.type,
    required this.plate,
    required this.year,
  });

  final String id;
  final VehicleType type;
  final String plate;
  final int year;
}

@Serializable()
class ResponseModel<T> {
  const ResponseModel({this.data, this.message});

  final T? data;
  final String? message;
}

@RestClient(baseUrl: 'https://api.example.test')
abstract class IntegrationVehicleApi {
  @HttpPost('/vehicles')
  Future<ResponseModel<VehicleResponse>> add(
    @Body() IntegrationVehicleRequest request,
  );

  @HttpGet('/vehicles')
  Future<ResponseModel<List<VehicleResponse>>> list();
}
