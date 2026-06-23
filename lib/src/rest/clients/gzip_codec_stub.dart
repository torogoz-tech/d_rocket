// Stub implementation of the gzip codec for
// the browser (no `dart:io`).
//
// On the browser, [gzipEncode] / [gzipDecode]
// throw [GzipUnavailableException] unless the
// user has set a polyfill via
// `GzipCodec.setPolyfill`. The polyfill
// delegates to the browser's native
// `CompressionStream` / `DecompressionStream`.

import 'compressed_http_client.dart' show GzipUnavailableException;

/// `true` if gzip is available on this
/// platform.
const bool isAvailable = false;

/// Compress [data] with gzip. Throws
/// [GzipUnavailableException] on the browser
/// unless a polyfill is set.
List<int> gzipEncode(List<int> data) {
  throw const GzipUnavailableException(
    'gzip is not available on the browser without a polyfill. '
    'Set GzipCodec.setPolyfill() from your main function, or use '
    'a server-side gateway (Cloudflare, nginx) to handle gzip.',
  );
}

/// Decompress [data] with gzip. Throws
/// [GzipUnavailableException] on the browser
/// unless a polyfill is set.
List<int> gzipDecode(List<int> data) {
  throw const GzipUnavailableException(
    'gzip is not available on the browser without a polyfill. '
    'Set GzipCodec.setPolyfill() from your main function.',
  );
}
