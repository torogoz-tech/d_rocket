import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../fixtures/integration_vehicle_api.dart';
import '../fixtures/integration_vehicle_request.dart';
import '../support/integration_vehicle_http_client.dart';

void main() {
  setUp(() {
    registerIntegrationVehicleRequestSerializer();
    registerVehicleResponseSerializer();
    registerResponseModelSerializer<VehicleResponse>(
      decode: (Object? value) => Serializer.fromDynamic<VehicleResponse>(value),
      encode: Serializer.encodeDynamic,
    );
    registerResponseModelSerializer<List<VehicleResponse>>(
      decode: (Object? value) => (value as List<dynamic>)
          .map(Serializer.fromDynamic<VehicleResponse>)
          .toList(),
      encode: Serializer.encodeDynamic,
    );
  });

  test('combined form and serializer codegen preserves enum and typed input',
      () {
    final IntegrationVehicleRequestForm form = IntegrationVehicleRequestForm();

    form.type.bindRaw()('truck');
    form.plate.bindRaw()('AB-1A');
    form.year.bindRaw()('2024');

    expect(
      form.validate(),
      isTrue,
      reason: form.state.fields
          .map(
            (String name, FormFieldState<Object?> field) =>
                MapEntry<String, String>(
              name,
              field.errors
                  .map((FormError error) => '${error.code}:${error.message}')
                  .toList()
                  .toString(),
            ),
          )
          .toString(),
    );
    final IntegrationVehicleRequest request = form.build();
    final Map<String, dynamic> json = request.toJson();

    expect(request.type, VehicleType.truck);
    expect(request.year, 2024);
    expect(json, <String, dynamic>{
      'type': 'truck',
      'plate': 'AB-1A',
      'year': 2024,
    });
  });

  test('generic response serialization preserves nullable data and enum types',
      () {
    final ResponseModel<VehicleResponse> response =
        ResponseModel<VehicleResponse>(
      data: const VehicleResponse(
        id: 'vehicle-1',
        type: VehicleType.car,
        plate: 'P-ABC',
        year: 2020,
      ),
    );

    final Map<String, dynamic> json = ResponseModelToJson<VehicleResponse>(
      response,
      Serializer.encodeDynamic,
    );
    final ResponseModel<VehicleResponse> restored =
        ResponseModelFromJson<VehicleResponse>(json, (Object? value) {
      return Serializer.fromDynamic<VehicleResponse>(value);
    });

    expect(restored.data?.type, VehicleType.car);
    expect(
      ResponseModelFromJson<VehicleResponse>(
        <String, dynamic>{'data': null},
        (Object? value) => Serializer.fromDynamic<VehicleResponse>(value),
      ).data,
      isNull,
    );
  });

  test('generated REST client preserves typed response contracts', () async {
    final IntegrationVehicleApi client = createIntegrationVehicleApi(
      config: RestClientConfig(client: IntegrationVehicleHttpClient()),
    );

    final ResponseModel<VehicleResponse> created = await client.add(
      IntegrationVehicleRequest(
        type: VehicleType.truck,
        plate: 'AB-1A',
        year: 2024,
      ),
    );
    final ResponseModel<List<VehicleResponse>> listed = await client.list();

    expect(created.data?.type, VehicleType.truck);
    expect(listed.data, hasLength(1));
    expect(listed.data?.single.plate, 'AB-1A');
  });
}
