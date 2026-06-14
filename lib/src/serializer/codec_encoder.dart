/// Encoder side of a value codec. Recursive values
/// are delegated back to the supplied [encode]
/// function so collections can recurse without
/// re-walking the codec table.
typedef CodecEncoder = Object? Function(Object? value);
