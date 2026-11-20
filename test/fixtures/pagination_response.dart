import 'package:d_rocket/d_rocket.dart';

part 'pagination_response.d_rocket_serializer.g.dart';

@Serializable()
class PaginationResponse {
  const PaginationResponse({required this.total});

  final int total;
}
