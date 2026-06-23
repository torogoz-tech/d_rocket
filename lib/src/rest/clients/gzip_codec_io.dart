// VM implementation of the gzip codec, backed
// by `dart:io.gzip` (built into the standard
// library, no extra dependency).

import 'dart:io' as io;

/// `true` if gzip is available on this
/// platform.
const bool isAvailable = true;

/// Compress [data] with gzip. Returns the
/// gzipped bytes. Equivalent to
/// `dart:io.gzip.encode(data)`.
List<int> gzipEncode(List<int> data) => io.gzip.encode(data);

/// Decompress [data] with gzip. Returns the
/// original bytes. Equivalent to
/// `dart:io.gzip.decode(data)`.
List<int> gzipDecode(List<int> data) => io.gzip.decode(data);
