import 'dart:async';

/// Mutable state for one normalized REST query.
class RestQueryCacheEntry {
  RestQueryCacheEntry({
    required this.key,
    required this.tags,
    required this.loader,
    required this.staleTime,
    required this.cacheTime,
  });

  final String key;
  final Set<String> tags;
  final Future<Object?> Function() loader;
  final Duration staleTime;
  final Duration cacheTime;
  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast();

  Future<Object?>? inFlight;
  Timer? evictionTimer;
  DateTime? loadedAt;
  Object? value;
  Object? error;
  StackTrace? errorStackTrace;
  bool hasValue = false;

  bool get isFresh =>
      hasValue &&
      loadedAt != null &&
      DateTime.now().difference(loadedAt!) < staleTime;

  void dispose() {
    evictionTimer?.cancel();
    evictionTimer = null;
  }
}
