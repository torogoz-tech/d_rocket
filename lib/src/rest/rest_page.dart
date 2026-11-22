/// A transport-neutral page contract for cursor or count-based REST APIs.
class RestPage<T> {
  const RestPage({
    required this.items,
    this.nextCursor,
    this.previousCursor,
    this.hasMore = false,
    this.totalCount,
  });

  final List<T> items;
  final String? nextCursor;
  final String? previousCursor;
  final bool hasMore;
  final int? totalCount;
}
