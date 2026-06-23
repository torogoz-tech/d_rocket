// 2.0.0 — HMAC request signing (real impl).
//
// Real HMAC-SHA256 / HMAC-SHA1 / HMAC-SHA512
// implementation backed by `package:crypto`.
// The `crypto` package is already a transitive
// dependency of d_rocket, so no extra dep is
// needed.
//
// ## Example
//
// ```dart
// final signer = HmacSha256Signer(utf8.encode('my-secret'));
// final signature = signer.signRequest(
//   method: 'GET',
//   url: 'https://api.example.com/v1/orders',
//   timestamp: '2026-06-22T10:00:00Z',
// );
// // Send `X-Signature: <signature>` as a header.
// ```

library;

import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

/// The hash algorithm to use. The default is
/// SHA-256 (recommended). SHA-1 is provided
/// for compatibility with legacy systems.
enum HmacAlgorithm {
  /// SHA-1 (legacy). 160-bit output.
  sha1,

  /// SHA-256 (recommended). 256-bit output.
  sha256,

  /// SHA-512. 512-bit output. Slower but
  /// stronger.
  sha512,
}

/// An HMAC signer. Computes HMAC signatures
/// over HTTP requests using a shared secret.
///
/// The signer is **stateless** — it doesn't
/// track request counters or nonces. If you
/// need a counter-based signature (like
/// AWS SigV4), compose this signer with your
/// own counter / nonce logic.
class HmacSha256Signer {
  /// Creates an [HmacSha256Signer] with the
  /// given [secret] (as bytes) and the
  /// [algorithm] (default SHA-256).
  HmacSha256Signer(
    this.secret, {
    this.algorithm = HmacAlgorithm.sha256,
  });

  /// The shared secret (raw bytes).
  final List<int> secret;

  /// The hash algorithm.
  final HmacAlgorithm algorithm;

  /// The size of the signature in bytes.
  /// 20 for SHA-1, 32 for SHA-256, 64 for
  /// SHA-512.
  int get signatureLength => switch (algorithm) {
        HmacAlgorithm.sha1 => 20,
        HmacAlgorithm.sha256 => 32,
        HmacAlgorithm.sha512 => 64,
      };

  /// Computes the HMAC of [message] (as
  /// bytes). Returns a `List<int>` of
  /// `signatureLength` bytes.
  List<int> signBytes(List<int> message) {
    final crypto.Hash hash = _hashFor(algorithm);
    final crypto.Hmac hmac = crypto.Hmac(hash, secret);
    return hmac.convert(message).bytes;
  }

  /// Computes the HMAC of [message] (as
  /// bytes). Returns the signature as a
  /// **lowercase hex** string.
  String signHex(List<int> message) {
    final List<int> bytes = signBytes(message);
    return _toHex(bytes);
  }

  /// Computes the HMAC of [message] (as
  /// bytes). Returns the signature as a
  /// base64-encoded string.
  String signBase64(List<int> message) {
    return base64.encode(signBytes(message));
  }

  /// Computes the HMAC for an HTTP request.
  /// The canonical string is:
  /// ```
  /// <method>\n<url>\n<base64(body)>\n<timestamp>
  /// ```
  /// Returns the signature as base64.
  String signRequest({
    required String method,
    required String url,
    List<int> body = const <int>[],
    required String timestamp,
  }) {
    final List<int> message = utf8.encode(
      '$method\n$url\n${base64.encode(body)}\n$timestamp',
    );
    return signBase64(message);
  }

  /// Verifies a signature. Returns `true` if
  /// the [expected] signature matches the
  /// HMAC of [message]. Uses constant-time
  /// comparison.
  bool verify(List<int> message, List<int> expected) {
    final List<int> actual = signBytes(message);
    if (actual.length != expected.length) return false;
    int diff = 0;
    for (int i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }

  static crypto.Hash _hashFor(HmacAlgorithm a) => switch (a) {
        HmacAlgorithm.sha1 => crypto.sha1,
        HmacAlgorithm.sha256 => crypto.sha256,
        HmacAlgorithm.sha512 => crypto.sha512,
      };

  static String _toHex(List<int> bytes) {
    final StringBuffer sb = StringBuffer();
    for (final int b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

/// Backwards-compatible alias for the original
/// 2.0.0 stub API. The new class is
/// [HmacSha256Signer]; this typedef is here
/// to keep the older import lines working.
typedef HmacSha256 = HmacSha256Signer;
