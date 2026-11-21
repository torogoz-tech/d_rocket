import 'package:test/test.dart';

import '../fixtures/uuid_request.dart';

void main() {
  test('generated UUID validators accept matching versions', () async {
    final UuidRequestForm form = UuidRequestForm(
      initialRequestId: '123e4567-e89b-4456-a456-426614174000',
      initialGeneralId: '123e4567-e89b-7456-a456-426614174000',
      initialVersionedId: '123e4567-e89b-7456-a456-426614174000',
    );

    expect(form.validate(), isTrue);
    await form.state.dispose();
  });

  test('generated UUID validators reject malformed and mismatched values',
      () async {
    final UuidRequestForm form = UuidRequestForm(
      initialRequestId: '123e4567-e89b-7456-a456-426614174000',
      initialGeneralId: '123e4567-e89b-c456-426614174000',
      initialVersionedId: '123e4567-e89b-4456-a456-426614174000',
    );

    expect(form.validate(), isFalse);
    expect(form.requestId.errorCode, 'uuid.invalid');
    expect(form.generalId.errorCode, 'uuid.invalid');
    await form.state.dispose();
  });

  test('nullable UUIDs accept null and preserve custom error metadata', () async {
    final UuidRequestForm form = UuidRequestForm(
      initialRequestId: '123e4567-e89b-4456-a456-426614174000',
      initialGeneralId: '123e4567-e89b-7456-a456-426614174000',
      initialVersionedId: '123e4567-e89b-7456-a456-426614174000',
    );

    expect(form.validate(), isTrue);
    form.optionalId.bindNullable()('not-a-uuid');

    expect(form.validate(), isFalse);
    expect(form.optionalId.errorCode, 'optional.uuid.invalid');
    expect(form.optionalId.error, 'UUID opcional inválido');
    await form.state.dispose();
  });
}
