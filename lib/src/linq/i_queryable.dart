import 'expr.dart';
import 'i_query_provider.dart';

/// A queryable source of `T` with deferred execution.
///
/// Iterating the queryable triggers the actual
/// computation. Multiple operators (where_, select_,
/// orderBy_, …) chain without materialising
/// intermediate results.
///
/// `IQueryable<T>` extends [Iterable`<T>`] so the
/// in-memory provider can be used anywhere an
/// `Iterable<T>` is expected. Note that this means
/// LINQ operators use the suffixed names (`where_`,
/// `select_`) to avoid clashing with the
/// closure-based [Iterable] methods.
abstract class IQueryable<T> extends Iterable<T> {
  /// The provider that owns this queryable.
  IQueryProvider get provider;

  /// The expression that produced this queryable,
  /// or `null` for a raw source (e.g.
  /// `users.asQueryable` with no operator applied).
  Expr? get expression;
}
