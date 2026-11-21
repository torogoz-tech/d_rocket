import 'package:d_rocket/d_rocket.dart';

part 'uuid_request.d_rocket_form.g.dart';

@Form()
class UuidRequest {
  UuidRequest({
    required this.requestId,
    required this.generalId,
    required this.versionedId,
    this.optionalId,
  });

  @Uuid(version: UuidVersion.v4)
  final String requestId;

  @Uuid()
  final String generalId;

  @Uuid(version: UuidVersion.v7)
  final String versionedId;

  @Uuid(message: 'UUID opcional inválido', code: 'optional.uuid.invalid')
  final String? optionalId;
}
