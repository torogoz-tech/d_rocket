// 2.0.0 — HmacSha256Signer tests.

import 'dart:convert';
import 'dart:typed_data';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('HmacSha256Signer (SHA-256):', () {
    test('signs a known payload with a known key (RFC 4231 test case 1)',
        () {
      // RFC 4231 test case 1:
      //   key  = 0x0b * 20
      //   data = "Hi There"
      //   expected HMAC-SHA-256 =
      //     b0344c61d8db38535ca8afceaf0bf12b
      //     881dc200c9833da726e9376c2e32cff7
      final Uint8List key = Uint8List(20)..fillRange(0, 20, 0x0b);
      final HmacSha256Signer signer = HmacSha256Signer(key);
      final String hex = signer.signHex(utf8.encode('Hi There'));
      expect(
        hex,
        'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7',
      );
    });

    test('signature length is 32 bytes (SHA-256)', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      expect(signer.signatureLength, 32);
      final List<int> sig =
          signer.signBytes(utf8.encode('hello'));
      expect(sig.length, 32);
    });

    test('different secrets produce different signatures', () {
      final HmacSha256Signer a = HmacSha256Signer(utf8.encode('a'));
      final HmacSha256Signer b = HmacSha256Signer(utf8.encode('b'));
      final List<int> msg = utf8.encode('hello');
      expect(
        a.signBytes(msg),
        isNot(equals(b.signBytes(msg))),
      );
    });

    test('verify: matching signature returns true', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      final List<int> msg = utf8.encode('hello');
      final List<int> sig = signer.signBytes(msg);
      expect(signer.verify(msg, sig), isTrue);
    });

    test('verify: tampered message returns false', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      final List<int> sig = signer.signBytes(utf8.encode('hello'));
      expect(signer.verify(utf8.encode('hellp'), sig), isFalse);
    });

    test('verify: wrong-length signature returns false', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      expect(
        signer.verify(utf8.encode('hello'), <int>[1, 2, 3]),
        isFalse,
      );
    });
  });

  group('HmacSha256Signer (SHA-1):', () {
    test('signs a known payload (RFC 2202 test case 1)', () {
      // RFC 2202 test case 1:
      //   key  = 0x0b * 20
      //   data = "Hi There"
      //   expected HMAC-SHA-1 =
      //     b617318655057264e28bc0b6fb378c8ef146be00
      final Uint8List key = Uint8List(20)..fillRange(0, 20, 0x0b);
      final HmacSha256Signer signer = HmacSha256Signer(
        key,
        algorithm: HmacAlgorithm.sha1,
      );
      final String hex = signer.signHex(utf8.encode('Hi There'));
      expect(hex, 'b617318655057264e28bc0b6fb378c8ef146be00');
    });

    test('SHA-1 signature is 20 bytes', () {
      final HmacSha256Signer signer = HmacSha256Signer(
        utf8.encode('secret'),
        algorithm: HmacAlgorithm.sha1,
      );
      expect(signer.signatureLength, 20);
    });
  });

  group('HmacSha256Signer (SHA-512):', () {
    test('SHA-512 signature is 64 bytes', () {
      final HmacSha256Signer signer = HmacSha256Signer(
        utf8.encode('secret'),
        algorithm: HmacAlgorithm.sha512,
      );
      expect(signer.signatureLength, 64);
    });
  });

  group('signRequest:', () {
    test('signs a request deterministically', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      final String a = signer.signRequest(
        method: 'GET',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:00Z',
      );
      final String b = signer.signRequest(
        method: 'GET',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:00Z',
      );
      expect(a, equals(b));
    });

    test('different timestamps produce different signatures', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      final String a = signer.signRequest(
        method: 'GET',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:00Z',
      );
      final String b = signer.signRequest(
        method: 'GET',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:01Z',
      );
      expect(a, isNot(equals(b)));
    });

    test('different methods produce different signatures', () {
      final HmacSha256Signer signer =
          HmacSha256Signer(utf8.encode('secret'));
      final String get = signer.signRequest(
        method: 'GET',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:00Z',
      );
      final String post = signer.signRequest(
        method: 'POST',
        url: 'https://api.example.com/v1/orders',
        timestamp: '2026-06-22T10:00:00Z',
      );
      expect(get, isNot(equals(post)));
    });
  });
}
