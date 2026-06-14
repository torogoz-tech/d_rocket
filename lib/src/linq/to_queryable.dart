import 'enumerable_query.dart';
import 'i_queryable.dart';

/// Sugar: lift an [Iterable] to [IQueryable].
extension ToQueryableExtension<T> on Iterable<T> {
  /// Returns an [IQueryable] view over this
  /// [Iterable]. The conversion is cheap — no
  /// elements are iterated until you call a
  /// terminal operator (e.g. `toList`, `forEach`,
  /// `first`).
  IQueryable<T> asQueryable() => EnumerableQuery<T>(this);
}
