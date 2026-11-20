import 'package:test/test.dart';

import '../fixtures/paginated_envelope.dart';
import '../fixtures/pagination_response.dart';

void main() {
  test('deserializes a present nullable nested model', () {
    registerPaginationResponseSerializer();
    registerPaginatedEnvelopeSerializer();

    final PaginatedEnvelope value = PaginatedEnvelopeFromJson(<String, dynamic>{
      'pagination': <String, dynamic>{'total': 42},
    });

    expect(value.pagination?.total, 42);
  });

  test('preserves null for a nullable nested model', () {
    registerPaginationResponseSerializer();
    registerPaginatedEnvelopeSerializer();

    final PaginatedEnvelope value = PaginatedEnvelopeFromJson(<String, dynamic>{
      'pagination': null,
    });

    expect(value.pagination, isNull);
  });
}
