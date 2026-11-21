import 'package:d_rocket/d_rocket.dart';

part 'uuid_request.d_rocket_form.g.dart';

@Form()
class UuidRequest {
  UuidRequest({required this.requestId, required this.generalId});

  @Uuid(version: UuidVersion.v4)
  final String requestId;

  @Uuid()
  final String generalId;
}
