import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

import 'fixtures/location_status.dart';
import 'fixtures/location_status_entity.dart';

void main() {
  setUp(() {
    EntityRegistry.reset();
    registerLocationStatusEntityEntityMeta();
  });

  test('serializes enum names and decodes unknown values with fallback', () {
    final LocationStatusEntity entity = LocationStatusEntity(
      id: 'location-1',
      status: LocationStatus.permissionDenied,
      optionalStatus: null,
    );

    final Map<String, dynamic> json = entity.toJson();
    final LocationStatusEntity restored =
        LocationStatusEntityFromJson(<String, dynamic>{
      'id': 'location-2',
      'status': 'futureStatus',
      'optionalStatus': null,
    });

    expect(json['status'], 'permissionDenied');
    expect(json['optionalStatus'], isNull);
    expect(restored.status, LocationStatus.unavailable);
    expect(restored.optionalStatus, isNull);
  });

  test('forms parse enum names and reject unsupported values', () {
    final LocationStatusEntityForm form = LocationStatusEntityForm();

    form.id.bindRaw()('location-form-1');
    form.status.bindRaw()('timeout');

    expect(form.status.value, LocationStatus.timeout);
    expect(form.build().status, LocationStatus.timeout);

    final LocationStatusEntityForm invalidForm = LocationStatusEntityForm();
    invalidForm.status.bindRaw()('not-a-location-status');

    expect(invalidForm.status.hasError, isTrue);
    expect(invalidForm.status.errorCode, 'conversion.invalid');
  });

  test('SQLite stores enum names and materializes text values', () {
    final EntityMeta meta = EntityRegistry.metaFor(LocationStatusEntity);
    final LocationStatusEntity entity = LocationStatusEntity(
      id: 'location-3',
      status: LocationStatus.available,
      optionalStatus: LocationStatus.pending,
    );

    expect(meta.createTableDdl(), contains('status TEXT'));
    expect(
      meta.readColumn!(
        entity,
        meta.columns.firstWhere(
          (ColumnMeta column) => column.dartField == 'status',
        ),
      ),
      'available',
    );

    final LocationStatusEntity restored = meta.fromRow!(<String, Object?>{
      'id': 'location-4',
      'status': 'pending',
      'optional_status': null,
    }) as LocationStatusEntity;

    expect(restored.status, LocationStatus.pending);
    expect(restored.optionalStatus, isNull);
  });

  test('SQLite applies the explicit unknown enum fallback', () {
    final EntityMeta meta = EntityRegistry.metaFor(LocationStatusEntity);

    final LocationStatusEntity restored = meta.fromRow!(<String, Object?>{
      'id': 'location-5',
      'status': 'futureStatus',
      'optional_status': null,
    }) as LocationStatusEntity;

    expect(restored.status, LocationStatus.unavailable);
  });
}
