import 'enumerable_query_provider.dart';
import 'expr.dart';
import 'i_query_provider.dart';
import 'i_queryable.dart';

/// An [IQueryable] backed by an [Iterable]. Used as
/// the root of every in-memory query, and also as
/// the result of operators that produce a new
/// queryable (e.g. `where_`).
class EnumerableQuery<T> extends IQueryable<T> {
  final Iterable<T> _source;
  final Expr? _expression;

  /// Wraps [source] as an [IQueryable]. If
  /// [expression] is provided, the queryable is
  /// "tagged" with it for debugging / round-trip
  /// purposes; the [iterator] still pulls from
  /// [source] directly.
  EnumerableQuery(this._source, [this._expression]);

  @override
  IQueryProvider get provider => EnumerableQueryProvider.instance;

  @override
  Expr? get expression => _expression;

  @override
  Iterator<T> get iterator => _source.iterator;
}
