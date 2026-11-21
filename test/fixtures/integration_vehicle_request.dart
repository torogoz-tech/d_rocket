import 'package:d_rocket/d_rocket.dart';

part 'integration_vehicle_request.d_rocket_form.g.dart';
part 'integration_vehicle_request.d_rocket_serializer.g.dart';

enum VehicleType { car, motorcycle, truck }

@Form()
@Serializable()
class IntegrationVehicleRequest {
  IntegrationVehicleRequest({
    required this.type,
    required this.plate,
    required this.year,
  });

  @Required()
  final VehicleType type;

  @Required()
  @Pattern(expression: r'^(P|N|AB|A)-[0-9A-F]{1,6}$')
  final String plate;

  @Required()
  @Range(min: 1886, max: 2100)
  @FormField(input: FormInput.number)
  final int year;
}
