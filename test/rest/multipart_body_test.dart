import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('encodes text and binary multipart parts', () {
    final RestMultipartBody body = RestMultipartBody(
      boundary: 'test-boundary',
      parts: <RestMultipartPart>[
        RestMultipartPart.field('name', 'Ada'),
        RestMultipartPart.bytes('document', <int>[1, 2], filename: 'a.bin'),
      ],
    );
    final String encoded = utf8.decode(body.toBytes());

    expect(body.contentType, 'multipart/form-data; boundary=test-boundary');
    expect(encoded, contains('name="name"'));
    expect(encoded, contains('Ada'));
    expect(encoded, contains('filename="a.bin"'));
    expect(body.toBytes(), contains(1));
    expect(encoded, endsWith('--test-boundary--\r\n'));
  });
}
