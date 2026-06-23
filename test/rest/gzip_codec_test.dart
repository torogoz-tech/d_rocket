// 2.0.0 — GzipCodec tests.

import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('GzipCodec (VM, dart:io):', () {
    test('encode then decode is identity', () {
      final List<int> data = utf8.encode('hello world ' * 100);
      final List<int> compressed = GzipCodec.encode(data);
      expect(compressed.length, lessThan(data.length));
      final List<int> decompressed = GzipCodec.decode(compressed);
      expect(utf8.decode(decompressed), 'hello world ' * 100);
    });

    test('encode of empty list returns a valid empty-gzip stream', () {
      final List<int> compressed = GzipCodec.encode(<int>[]);
      // An empty gzip stream is 20 bytes.
      expect(compressed.length, 20);
      // Round-trip.
      expect(GzipCodec.decode(compressed), <int>[]);
    });

    test('decode of a known gzipped payload', () {
      // The string "foo" gzipped.
      final List<int> data = utf8.encode('foo');
      final List<int> compressed = GzipCodec.encode(data);
      expect(GzipCodec.decode(compressed), data);
    });

    test('isAvailable is true on the VM', () {
      expect(GzipCodec.isAvailable, isTrue);
    });
  });

  group('CompressedBody marker:', () {
    test('default encoding is "gzip"', () {
      const CompressedBody cb = CompressedBody(<int>[1, 2, 3]);
      expect(cb.encoding, 'gzip');
      expect(cb.body, <int>[1, 2, 3]);
    });

    test('can override encoding to deflate', () {
      const CompressedBody cb = CompressedBody(
        <int>[1, 2, 3],
        encoding: 'deflate',
      );
      expect(cb.encoding, 'deflate');
    });
  });

  group('GzipUnavailableException:', () {
    test('toString includes the message', () {
      const GzipUnavailableException e =
          GzipUnavailableException('nope');
      expect(e.toString(), contains('nope'));
    });
  });
}
