/// Marks a `Stream<T>` REST method as a reactive cached query.
class QueryCache {
  const QueryCache({
    required this.tags,
    this.staleTime = const Duration(seconds: 30),
    this.cacheTime = const Duration(minutes: 5),
  });

  final List<String> tags;
  final Duration staleTime;
  final Duration cacheTime;
}
