// REST.1 — HttpCache tests (ETag-based caching)

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('HttpCache:', () {
    test('starts empty', () {
      final HttpCache cache = HttpCache();
      expect(cache.entryCount, 0);
      expect(cache.hits, 0);
      expect(cache.misses, 0);
      expect(cache.revalidations, 0);
    });

    test('miss on first get', () {
      final HttpCache cache = HttpCache();
      expect(cache.get('key1'), isNull);
      expect(cache.misses, 1);
      expect(cache.hits, 0);
    });

    test('put then get: hit', () {
      final HttpCache cache = HttpCache();
      cache.put('key1', CacheEntry(
        body: <int>[1, 2, 3],
        etag: 'etag-1',
        fetchedAt: DateTime.now(),
      ));
      final CacheEntry? e = cache.get('key1');
      expect(e, isNotNull);
      expect(e!.body, <int>[1, 2, 3]);
      expect(e.etag, 'etag-1');
      expect(cache.hits, 1);
      expect(cache.misses, 0);
    });

    test('get returns null when maxAge exceeded', () {
      final HttpCache cache = HttpCache(maxAge: Duration.zero);
      cache.put('key1', CacheEntry(
        body: <int>[1, 2, 3],
        etag: 'etag-1',
        fetchedAt: DateTime(2020),
      ));
      expect(cache.get('key1'), isNull);
      expect(cache.misses, 1);
    });

    test('maxEntries evicts oldest', () {
      final HttpCache cache = HttpCache(
        maxEntries: 2,
        maxAge: const Duration(days: 365 * 100),
      );
      cache.put('key1', CacheEntry(
        body: <int>[1],
        etag: null,
        fetchedAt: DateTime(2020, 1, 1),
      ));
      cache.put('key2', CacheEntry(
        body: <int>[2],
        etag: null,
        fetchedAt: DateTime(2020, 1, 2),
      ));
      cache.put('key3', CacheEntry(
        body: <int>[3],
        etag: null,
        fetchedAt: DateTime(2020, 1, 3),
      ));
      expect(cache.entryCount, 2);
      expect(cache.get('key1'), isNull); // evicted (oldest)
      expect(cache.get('key2'), isNotNull);
      expect(cache.get('key3'), isNotNull);
    });

    test('clear empties the cache', () {
      final HttpCache cache = HttpCache();
      cache.put('key1', CacheEntry(
        body: <int>[1],
        etag: null,
        fetchedAt: DateTime.now(),
      ));
      expect(cache.entryCount, 1);
      cache.clear();
      expect(cache.entryCount, 0);
    });

    test('recordRevalidation bumps the counter', () {
      final HttpCache cache = HttpCache();
      cache.recordRevalidation();
      cache.recordRevalidation();
      expect(cache.revalidations, 2);
    });

    test('keyFor builds the right key', () {
      final HttpCache cache = HttpCache();
      expect(
        cache.keyFor('GET', Uri.parse('https://example.com/a')),
        'GET https://example.com/a',
      );
    });
  });
}
