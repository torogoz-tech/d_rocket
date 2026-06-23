// 2.0.0 — Compression middleware (real impl).
//
// On the VM (server / desktop / mobile), uses
// `dart:io.gzip` which is built into the Dart
// standard library.
//
// On the browser, `dart:io` is not available.
// The browser fallback is **optional** — if the
// user has not configured a polyfill, gzip
// compression / decompression becomes a
// passthrough (the browser's fetch API
// transparently handles `Content-Encoding:
// gzip`, so this is fine in practice).
//
// To enable gzip on the web, the user can
// either:
//   1. Add a JS interop layer that calls the
//      browser's native `CompressionStream` /
//      `DecompressionStream`.
//   2. Use a server-side gateway that gzips
//      responses (Cloudflare, nginx).
//
// ## Architecture
//
// `GzipCodec` (in this file) is a thin static
// facade. The actual `dart:io` work happens
// in `gzip_codec_io.dart` (only imported on
// the VM via a conditional import). The
// browser sees a no-op codec.

library;

import 'gzip_codec_stub.dart'
    if (dart.library.io) 'gzip_codec_io.dart' as codec;

/// Thrown by [GzipCodec.encode] / [decode]
/// when the platform has no gzip support and no
/// polyfill is set.
class GzipUnavailableException implements Exception {
  /// Creates a [GzipUnavailableException].
  const GzipUnavailableException(this.message);
  final String message;
  @override
  String toString() => 'GzipUnavailableException: $message';
}

/// A marker for a request that's been
/// compressed. The actual compression is
/// applied by the wrapper client.
class CompressedBody {
  /// Creates a [CompressedBody].
  const CompressedBody(this.body, {this.encoding = 'gzip'});

  /// The compressed body.
  final List<int> body;

  /// The encoding (`gzip`, `deflate`, etc.).
  final String encoding;
}

/// A codec for gzip compression / decompression.
///
/// On the VM, uses `dart:io.gzip` (built-in,
/// fast). On the browser, throws
/// [GzipUnavailableException] unless a polyfill
/// is set via [setPolyfill].
class GzipCodec {
  /// Optional user-supplied polyfills. If
  /// [setPolyfill] is called with both
  /// [encode] and [decode], they are used
  /// instead of dart:io (typically on the
  /// browser, where the user wires up
  /// `CompressionStream` / `DecompressionStream`
  /// via JS interop).
  static List<int> Function(List<int>)? _encoderOverride;
  static List<int> Function(List<int>)? _decoderOverride;

  /// Sets the user-supplied polyfills. The
  /// browser calls this with functions that
  /// delegate to `CompressionStream` /
  /// `DecompressionStream`. Pass `null` for
  /// both arguments to clear the polyfill.
  static void setPolyfill({
    List<int> Function(List<int>)? encode,
    List<int> Function(List<int>)? decode,
  }) {
    _encoderOverride = encode;
    _decoderOverride = decode;
  }

  /// Compress [data] with gzip. Returns the
  /// gzipped bytes. On the VM this is
  /// `dart:io.gzip.encode(data)`. On the
  /// browser it throws unless a polyfill is
  /// set.
  static List<int> encode(List<int> data) {
    if (_encoderOverride != null) {
      return _encoderOverride!(data);
    }
    return codec.gzipEncode(data);
  }

  /// Decompress [data] with gzip. Returns the
  /// original bytes. On the VM this is
  /// `dart:io.gzip.decode(data)`. On the
  /// browser it throws unless a polyfill is
  /// set.
  static List<int> decode(List<int> data) {
    if (_decoderOverride != null) {
      return _decoderOverride!(data);
    }
    return codec.gzipDecode(data);
  }

  /// Whether gzip is available right now
  /// (either via dart:io on the VM or via a
  /// user polyfill on the browser).
  static bool get isAvailable => codec.isAvailable;
}
