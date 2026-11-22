import 'dart:convert';

import 'rest_multipart_part.dart';

/// Encodes multipart parts into a request body accepted by `package:http`.
class RestMultipartBody {
  RestMultipartBody({
    required List<RestMultipartPart> parts,
    String? boundary,
  })  : parts = List<RestMultipartPart>.unmodifiable(parts),
        boundary = boundary ?? _newBoundary();

  final List<RestMultipartPart> parts;
  final String boundary;

  String get contentType => 'multipart/form-data; boundary=$boundary';

  List<int> toBytes() {
    final List<int> output = <int>[];
    for (final RestMultipartPart part in parts) {
      output.addAll(utf8.encode('--$boundary\r\n'));
      final String disposition = part.filename == null
          ? 'form-data; name="${_escape(part.name)}"'
          : 'form-data; name="${_escape(part.name)}"; '
              'filename="${_escape(part.filename!)}"';
      output.addAll(utf8.encode('Content-Disposition: $disposition\r\n'));
      output.addAll(utf8.encode('Content-Type: ${part.contentType}\r\n\r\n'));
      output.addAll(part.bytes);
      output.addAll(utf8.encode('\r\n'));
    }
    output.addAll(utf8.encode('--$boundary--\r\n'));
    return output;
  }
}

String _escape(String value) => value.replaceAll('"', '%22');

String _newBoundary() =>
    'drocket-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
