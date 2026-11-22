/// Defaults used by an instance of [RestQueryCache].
class RestQueryCacheOptions {
  const RestQueryCacheOptions({
    this.staleTime = const Duration(seconds: 30),
    this.cacheTime = const Duration(minutes: 5),
  });

  final Duration staleTime;
  final Duration cacheTime;
}
