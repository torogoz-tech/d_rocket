// 2.0.0 — HTTP cache utility.
//
// The actual cache integration into the REST
// pipeline happens at the `DRest` level (see
// `rest_client.dart`). This file provides the
// building block: a thread-safe in-memory
// cache with ETag tracking.
//
// The actual ETag / If-None-Match flow is
// applied by a small `CachedHttpClient`
// wrapper that the user attaches in front of
// any [HttpClient] implementation. The flow:
//
// 1. First request: send to the server, get
//    back a 200 + ETag header. Store the
//    body and the ETag.
// 2. Second request: send with
//    `If-None-Match: <etag>`. If the server
//    returns 304, return the cached body.

library;

/// A cache entry: body + ETag + last-fetched
/// time.
class CacheEntry {
  /// Creates a [CacheEntry].
  const CacheEntry({
    required this.body,
    required this.etag,
    required this.fetchedAt,
  });

  /// The cached body (as a `List<int>` so it
  /// works for both JSON and binary).
  final List<int> body;

  /// The ETag (or `null` if the response
  /// didn't have one).
  final String? etag;

  /// When this entry was fetched.
  final DateTime fetchedAt;
}

/// An in-memory ETag cache for HTTP
/// responses. Thread-safe (uses a lock-free
/// single-threaded model — Dart is
/// single-threaded per isolate).
class HttpCache {
  /// Creates an [HttpCache] with [maxEntries]
  /// (default 1000) and [maxAge] (default
  /// 1 hour).
  HttpCache({this.maxEntries = 1000, this.maxAge = const Duration(hours: 1)});

  /// Maximum number of entries.
  final int maxEntries;

  /// Maximum age before revalidation.
  final Duration maxAge;

  final Map<String, CacheEntry> _cache = <String, CacheEntry>{};
  int _hits = 0;
  int _misses = 0;
  int _revalidations = 0;

  /// Number of cache hits.
  int get hits => _hits;

  /// Number of cache misses.
  int get misses => _misses;

  /// Number of 304 Not Modified responses.
  int get revalidations => _revalidations;

  /// The current number of entries in the
  /// cache.
  int get entryCount => _cache.length;

  /// Empties the cache.
  void clear() {
    _cache.clear();
  }

  /// The cache key for a `method + url`
  /// combination.
  String keyFor(String method, Uri url) => '$method ${url.toString()}';

  /// The cached entry for [key], or `null` if
  /// not in the cache. Bumps the `hits` or
  /// `misses` counter.
  CacheEntry? get(String key) {
    final CacheEntry? entry = _cache[key];
    if (entry == null) {
      _misses++;
      return null;
    }
    if (DateTime.now().difference(entry.fetchedAt) > maxAge) {
      _misses++;
      return null;
    }
    _hits++;
    return entry;
  }

  /// Stores a new entry for [key]. Evicts
  /// the oldest entry if we're over
  /// [maxEntries].
  void put(String key, CacheEntry entry) {
    _cache[key] = entry;
    if (_cache.length > maxEntries) {
      final String oldestKey = _cache.entries
          .reduce((MapEntry<String, CacheEntry> a,
                  MapEntry<String, CacheEntry> b) =>
              a.value.fetchedAt.isBefore(b.value.fetchedAt) ? a : b)
          .key;
      _cache.remove(oldestKey);
    }
  }

  /// Records a 304 Not Modified response (the
  /// revalidation succeeded).
  void recordRevalidation() {
    _revalidations++;
  }
}
