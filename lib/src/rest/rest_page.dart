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

  factory RestPage.fromJson(
    Map<String, dynamic> json,
    T Function(Object? value) decodeItem,
  ) {
    final Object? rawItems = json['items'];
    if (rawItems is! List<Object?>) {
      throw FormatException('RestPage.items must be a JSON array.');
    }
    return RestPage<T>(
      items: rawItems.map(decodeItem).toList(),
      nextCursor: json['nextCursor'] as String?,
      previousCursor: json['previousCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
      totalCount: (json['totalCount'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson(Object? Function(T value) encodeItem) {
    return <String, dynamic>{
      'items': items.map(encodeItem).toList(),
      'nextCursor': nextCursor,
      'previousCursor': previousCursor,
      'hasMore': hasMore,
      'totalCount': totalCount,
    };
  }
}
