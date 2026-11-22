import 'package:d_rocket/d_rocket.dart';

part 'transfer_request.d_rocket_serializer.g.dart';

@Serializable()
class TransferRequest {
  const TransferRequest({required this.sourceAccountId});

  final String sourceAccountId;
}
