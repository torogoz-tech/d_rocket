import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import 'package:d_rocket/example/integration_vehicle_api.dart';
import 'package:d_rocket/example/integration_vehicle_request.dart';
import 'package:d_rocket/d_rocket_registry.g.dart';
import '../support/integration_vehicle_http_client.dart';

void main() {
  setUp(() {
    initializeD();
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

    expect(request.type, IntegrationVehicleType.truck);
    expect(request.year, 2024);
    expect(json, <String, dynamic>{
      'type': 'truck',
      'plate': 'AB-1A',
      'year': 2024,
    });
  });

  test('generic response serialization preserves nullable data and enum types',
      () {
    final IntegrationResponse<IntegrationVehicleResponse> response =
        IntegrationResponse<IntegrationVehicleResponse>(
      data: const IntegrationVehicleResponse(
        id: 'vehicle-1',
        type: IntegrationVehicleType.car,
        plate: 'P-ABC',
        year: 2020,
      ),
    );

    final Map<String, dynamic> json =
        IntegrationResponseToJson<IntegrationVehicleResponse>(
      response,
      Serializer.encodeDynamic,
    );
    final IntegrationResponse<IntegrationVehicleResponse> restored =
        IntegrationResponseFromJson<IntegrationVehicleResponse>(json, (Object? value) {
      return Serializer.fromDynamic<IntegrationVehicleResponse>(value);
    });

    expect(restored.data?.type, IntegrationVehicleType.car);
    expect(
      IntegrationResponseFromJson<IntegrationVehicleResponse>(
        <String, dynamic>{'data': null},
        (Object? value) => Serializer.fromDynamic<IntegrationVehicleResponse>(value),
      ).data,
      isNull,
    );
    expect(
      () => IntegrationVehicleResponseFromJson(<String, dynamic>{
        'id': 'vehicle-unknown',
        'type': 'scooter',
        'plate': 'P-ABC',
        'year': 2020,
      }),
      throwsArgumentError,
    );
  });

  test('generated REST client preserves typed response contracts', () async {
    final IntegrationVehicleApi client = createIntegrationVehicleApi(
      config: RestClientConfig(client: IntegrationVehicleHttpClient()),
    );

    final IntegrationResponse<IntegrationVehicleResponse> created = await client.add(
      IntegrationVehicleRequest(
        type: IntegrationVehicleType.truck,
        plate: 'AB-1A',
        year: 2024,
      ),
    );
    final IntegrationResponse<List<IntegrationVehicleResponse>> listed =
        await client.list();

    expect(created.data?.type, IntegrationVehicleType.truck);
    expect(listed.data, hasLength(1));
    expect(listed.data?.single.plate, 'AB-1A');
  });
}
