import 'package:d_rocket/d_rocket.dart';

import 'integration_vehicle_request.dart';

part 'integration_vehicle_api.d_rocket_serializer.g.dart';
part 'integration_vehicle_api.d_rocket_rest_client.g.dart';

@Serializable()
class IntegrationVehicleResponse {
  const IntegrationVehicleResponse({
    required this.id,
    required this.type,
    required this.plate,
    required this.year,
  });

  final String id;
  final IntegrationVehicleType type;
  final String plate;
  final int year;
}

@Serializable()
class IntegrationResponse<T> {
  const IntegrationResponse({this.data, this.message});

  final T? data;
  final String? message;
}

@RestClient(baseUrl: 'https://api.example.test')
abstract class IntegrationVehicleApi {
  @HttpPost('/vehicles')
  Future<IntegrationResponse<IntegrationVehicleResponse>> add(
    @Body() IntegrationVehicleRequest request,
  );

  @HttpGet('/vehicles')
  Future<IntegrationResponse<List<IntegrationVehicleResponse>>> list();
}
