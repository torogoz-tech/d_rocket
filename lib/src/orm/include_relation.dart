//: declarative eager loading. The
// `DbSet<T>.findById(id, joins: [...])` API accepts
// a list of `IncludeRelation`s. Each one tells the
// runtime what to eager-load.
//
// This file is the parent library; the subtypes
// (`IncludeOne` for @BelongsTo and `IncludeMany` for
// @HasMany) live in part files so they can
// extend the sealed [IncludeRelation] (Dart 3's
// `sealed` requires all subtypes to be in the same
// library).

library;

import 'entity_meta.dart';

part 'include_many.dart';
part 'include_one.dart';

/// A relation to be eager-loaded by
/// `DbSet<T>.findById(id, joins: [...])`.
///
/// `IncludeRelation` is sealed: only the
/// documented subtypes ([IncludeOne] for @BelongsTo
/// and [IncludeMany] for @HasMany) can be
/// instantiated.
sealed class IncludeRelation<T, R> {
  /// The navigation property name on `T`
  /// (e.g. `'author'`, `'sales'`).
  final String navigationName;

  /// The EntityMeta of the related table. Used
  /// by the runtime to materialise the related rows
  /// via `EntityMeta.fromRow`.
  final EntityMeta relatedMeta;

  const IncludeRelation({
    required this.navigationName,
    required this.relatedMeta,
  });
}
