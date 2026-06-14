/// The set-operation LINQ operators.
///
/// * `union_(other)` — elements in either [this] or [other] (no dups).
/// * `intersect_(other)` — elements in both [this] and [other].
/// * `except_(other)` — elements in [this] but not in [other].
///
/// All three use Dart's `==` (and `hashCode`) for equality.
///
/// In (SQLite) these translate to `UNION`, `INTERSECT`,
/// and `EXCEPT` respectively.
library;

import '../enumerable_query.dart';
import '../i_queryable.dart';

extension SetOps<T> on IQueryable<T> {
  /// Returns the set union of this queryable and [other].
  ///
  /// Duplicates are removed; the result preserves the first-occurrence
  /// order of [this], then the first-occurrence order of [other].
  ///
  /// Example:
  ///
  /// ```dart
  /// final a = [1, 2, 3].asQueryable;
  /// final b = [3, 4, 5].asQueryable;
  /// final result = a.union_(b).toList;
  /// // → [1, 2, 3, 4, 5]
  /// ```
  IQueryable<T> union_(IQueryable<T> other) {
    final seen = <T>{};
    final out = <T>[];
    for (final e in this) {
      if (seen.add(e)) out.add(e);
    }
    for (final e in other) {
      if (seen.add(e)) out.add(e);
    }
    return EnumerableQuery<T>(out);
  }

  /// Returns the set intersection of this queryable and [other].
  ///
  /// The result preserves the first-occurrence order of [this].
  ///
  /// Example:
  ///
  /// ```dart
  /// final a = [1, 2, 3, 4].asQueryable;
  /// final b = [3, 4, 5, 6].asQueryable;
  /// final result = a.intersect_(b).toList;
  /// // → [3, 4]
  /// ```
  IQueryable<T> intersect_(IQueryable<T> other) {
    final others = other.toSet();
    final seen = <T>{};
    final out = <T>[];
    for (final e in this) {
      if (others.contains(e) && seen.add(e)) out.add(e);
    }
    return EnumerableQuery<T>(out);
  }

  /// Returns the set difference: elements in this queryable that are
  /// not in [other].
  ///
  /// Preserves the order of [this] and deduplicates the result.
  ///
  /// Example:
  ///
  /// ```dart
  /// final a = [1, 2, 3, 4].asQueryable;
  /// final b = [3, 4].asQueryable;
  /// final result = a.except_(b).toList;
  /// // → [1, 2]
  /// ```
  IQueryable<T> except_(IQueryable<T> other) {
    final excluded = other.toSet();
    final seen = <T>{};
    final out = <T>[];
    for (final e in this) {
      if (!excluded.contains(e) && seen.add(e)) out.add(e);
    }
    return EnumerableQuery<T>(out);
  }
}
