import 'expr.dart';
import 'i_query_provider.dart';
import 'i_queryable.dart';

/// The default in-memory provider. Singleton.
///
/// Use [EnumerableQueryProvider.instance] to obtain it.
class EnumerableQueryProvider implements IQueryProvider {
  EnumerableQueryProvider._();

  static final EnumerableQueryProvider instance = EnumerableQueryProvider._();

  @override
  IQueryable<T> createQuery<T>(Expr expression) {
    throw UnsupportedError(
      'EnumerableQueryProvider.createQuery is not implemented. '
      'Use `asQueryable()` on a source Iterable, then chain '
      'operators such as `where_` and `select_`.',
    );
  }

  @override
  TResult execute<TResult>(Expr expression) {
    throw UnsupportedError(
      'EnumerableQueryProvider.execute is not implemented. '
      'Use the closure-based Iterable methods (count, fold, etc.) for now.',
    );
  }
}
