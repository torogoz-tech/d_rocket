import 'package:d_rocket/d_rocket.dart';

import 'location_status.dart';

part 'location_status_entity.d_rocket_form.g.dart';
part 'location_status_entity.d_rocket_orm.g.dart';
part 'location_status_entity.d_rocket_serializer.g.dart';

@Serializable()
@Form()
@Table()
class LocationStatusEntity {
  LocationStatusEntity({
    required this.id,
    required this.status,
    required this.optionalStatus,
  });

  @PrimaryKey()
  final String id;

  @Column()
  @JsonKey(unknownEnumValue: 'unavailable')
  final LocationStatus status;

  @Column()
  final LocationStatus? optionalStatus;
}
