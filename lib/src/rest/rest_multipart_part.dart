import 'dart:convert';

/// One field or binary part in a multipart REST body.
class RestMultipartPart {
  const RestMultipartPart._({
    required this.name,
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  factory RestMultipartPart.field(String name, String value) {
    return RestMultipartPart._(
      name: name,
      bytes: utf8.encode(value),
      filename: null,
      contentType: 'text/plain; charset=utf-8',
    );
  }

  factory RestMultipartPart.bytes(
    String name,
    List<int> bytes, {
    String? filename,
    String contentType = 'application/octet-stream',
  }) {
    return RestMultipartPart._(
      name: name,
      bytes: List<int>.unmodifiable(bytes),
      filename: filename,
      contentType: contentType,
    );
  }

  factory RestMultipartPart.fromValue(String name, Object? value) {
    if (value is RestMultipartPart) return value;
    if (value is List<int>) return RestMultipartPart.bytes(name, value);
    return RestMultipartPart.field(name, value?.toString() ?? '');
  }

  final String name;
  final List<int> bytes;
  final String? filename;
  final String contentType;
}
