import 'package:d_rocket/d_rocket.dart';

import 'pagination_response.dart';

part 'paginated_envelope.d_rocket_serializer.g.dart';

@Serializable()
class PaginatedEnvelope {
  const PaginatedEnvelope({required this.pagination});

  final PaginationResponse? pagination;
}
