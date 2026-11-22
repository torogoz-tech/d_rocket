/// Dependency-free deep equality for generated value models.
class ValueEquality {
  ValueEquality._();

  /// Compares supported nested values without relying on a UI state package.
  static bool equals(Object? left, Object? right) {
    return _equals(left, right, <int>{});
  }

  /// Produces a deterministic hash for supported nested values.
  static int hash(Object? value) {
    return _hash(value, <int>{});
  }

  static bool _equals(Object? left, Object? right, Set<int> active) {
    if (identical(left, right)) return true;
    if (left == null || right == null || left.runtimeType != right.runtimeType) {
      return false;
    }
    final int identity = identityHashCode(left);
    if (!active.add(identity)) return true;
    try {
      if (left is List<Object?> && right is List<Object?>) {
        if (left.length != right.length) return false;
        for (var index = 0; index < left.length; index++) {
          if (!_equals(left[index], right[index], active)) return false;
        }
        return true;
      }
      if (left is Set<Object?> && right is Set<Object?>) {
        if (left.length != right.length) return false;
        return left.every(
          (Object? item) => right.any(
            (Object? candidate) => _equals(item, candidate, active),
          ),
        );
      }
      if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
        if (left.length != right.length) return false;
        for (final MapEntry<Object?, Object?> entry in left.entries) {
          if (!right.keys.any(
            (Object? key) => _equals(entry.key, key, active),
          )) {
            return false;
          }
          final Object? matchingKey = right.keys.firstWhere(
            (Object? key) => _equals(entry.key, key, active),
          );
          if (!_equals(entry.value, right[matchingKey], active)) return false;
        }
        return true;
      }
      return left == right;
    } finally {
      active.remove(identity);
    }
  }

  static int _hash(Object? value, Set<int> active) {
    if (value == null) return 0;
    if (value is List<Object?>) {
      final int identity = identityHashCode(value);
      if (!active.add(identity)) return 0;
      try {
        return value.fold<int>(
          17,
          (int result, Object? item) => _combine(result, _hash(item, active)),
        );
      } finally {
        active.remove(identity);
      }
    }
    if (value is Set<Object?>) {
      final List<int> hashes = value.map((Object? item) => _hash(item, active)).toList()
        ..sort();
      return hashes.fold<int>(17, _combine);
    }
    if (value is Map<Object?, Object?>) {
      final List<int> hashes = value.entries
          .map((MapEntry<Object?, Object?> entry) =>
              _combine(_hash(entry.key, active), _hash(entry.value, active)))
          .toList()
        ..sort();
      return hashes.fold<int>(17, _combine);
    }
    return value.hashCode;
  }

  static int _combine(int left, int right) => 0x1fffffff & (left * 31 + right);
}
