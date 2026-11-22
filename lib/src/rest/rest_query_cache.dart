import 'dart:async';

import 'query_cache_entry.dart';
import 'rest_query_cache_options.dart';

/// Reactive, instance-scoped cache for network-first REST queries.
///
/// A key identifies one normalized request. Concurrent subscribers share the
/// same loader and active entries can be refetched by tag invalidation. The
/// cache does not know about Flutter or a presentation-state package.
class RestQueryCache {
  RestQueryCache({RestQueryCacheOptions options = const RestQueryCacheOptions()})
      : _options = options;

  final RestQueryCacheOptions _options;
  final Map<String, RestQueryCacheEntry> _entries =
      <String, RestQueryCacheEntry>{};
  int _generation = 0;

  /// Number of currently registered query entries.
  int get entryCount => _entries.length;

  /// Watches a query and deduplicates concurrent calls for [key].
  Stream<T> watch<T>({
    required String key,
    required Iterable<String> tags,
    required Future<T> Function() loader,
    Duration? staleTime,
    Duration? cacheTime,
  }) {
    final RestQueryCacheEntry? existing = _entries[key];
    final RestQueryCacheEntry entry = existing ??
        RestQueryCacheEntry(
          key: key,
          tags: tags.toSet(),
          loader: () async => loader(),
          staleTime: staleTime ?? _options.staleTime,
          cacheTime: cacheTime ?? _options.cacheTime,
        );
    if (existing == null) {
      _entries[key] = entry;
    }

    scheduleMicrotask(() {
      if (_entries[key] != entry || entry.controller.isClosed) {
        return;
      }
      if (entry.isFresh) {
        entry.controller.add(entry.value);
        return;
      }
      _load(entry, _generation);
    });

    return entry.controller.stream.map((Object? value) => value as T);
  }

  /// Refetches active queries whose tag set intersects [tags].
  Future<void> invalidate(Iterable<String> tags) async {
    final Set<String> invalidated = tags.toSet();
    final List<Future<Object?>> reloads = <Future<Object?>>[];
    for (final RestQueryCacheEntry entry in _entries.values.toList()) {
      if (entry.tags.intersection(invalidated).isEmpty) {
        continue;
      }
      entry.loadedAt = null;
      if (entry.controller.hasListener) {
        reloads.add(_load(entry, _generation));
      }
    }
    await Future.wait(reloads);
  }

  /// Removes all values and registrations.
  ///
  /// A generation change prevents an older in-flight response from emitting
  /// or repopulating the cache after a logout or account switch.
  Future<void> clear() async {
    _generation++;
    final List<Future<void>> closures = <Future<void>>[];
    for (final RestQueryCacheEntry entry in _entries.values) {
      entry.dispose();
      closures.add(entry.controller.close());
    }
    _entries.clear();
    await Future.wait(closures);
  }

  Future<Object?> _load(RestQueryCacheEntry entry, int generation) {
    final Future<Object?>? current = entry.inFlight;
    if (current != null) {
      return current;
    }
    final Future<Object?> operation = Future<Object?>.sync(entry.loader);
    entry.inFlight = operation;
    final Future<Object?> completed = operation.then<Object?>((Object? value) {
      if (_entries[entry.key] == entry && generation == _generation) {
        entry.value = value;
        entry.hasValue = true;
        entry.error = null;
        entry.errorStackTrace = null;
        entry.loadedAt = DateTime.now();
        entry.controller.add(value);
        _scheduleEviction(entry, generation);
      }
      return value;
    }, onError: (Object error, StackTrace stackTrace) {
      if (_entries[entry.key] == entry && generation == _generation) {
        entry.error = error;
        entry.errorStackTrace = stackTrace;
        entry.controller.addError(error, stackTrace);
      }
      return null;
    });
    entry.inFlight = completed;
    completed.then<void>((Object? _) {
      if (entry.inFlight == completed) {
        entry.inFlight = null;
      }
    }, onError: (Object _, StackTrace __) {
      if (entry.inFlight == completed) {
        entry.inFlight = null;
      }
    });
    return completed;
  }

  void _scheduleEviction(RestQueryCacheEntry entry, int generation) {
    entry.evictionTimer?.cancel();
    entry.evictionTimer = Timer(entry.cacheTime, () {
      if (_entries[entry.key] == entry && generation == _generation) {
        _entries.remove(entry.key);
        entry.dispose();
      }
    });
  }
}
