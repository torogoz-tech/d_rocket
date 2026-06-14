import 'expr.dart';
import 'i_queryable.dart';

/// A backend that can execute LINQ expressions.
abstract interface class IQueryProvider {
  /// Creates a new [IQueryable] from a root [expression].
  ///
  /// The expression is the head of the tree; providers
  /// are expected to know how to interpret it (e.g.
  /// `Expr.lambda(...)`).
  IQueryable<T> createQuery<T>(Expr expression);

  /// Executes a scalar expression (e.g. `Count`, `Sum`).
  ///
  /// Throws [UnsupportedError] if the provider cannot
  /// evaluate the expression.
  TResult execute<TResult>(Expr expression);
}
