// .e — `DbSetInclude`:
//
// A small data class holding the parameters of a
// pending navigation include on a `DbSet<T>`. The
// user calls `.include_<TNav>(name, targetMeta)` on
// the DbSet to enqueue one; the DbSet applies them
// in `toListWithIncludesAsync_`.
//
// One DbSetInclude per navigation. Multiple
// includes on the same DbSet are processed in
// order (FIFO).

import 'entity_meta.dart';

/// .e: a pending navigation include.
class DbSetInclude {
  /// The navigation name (must match a
  /// [NavigationMeta.name] in the source's
  /// EntityMeta).
  final String name;

  /// The EntityMeta of the target entity. Used by
  /// [NavigationPopulator] to materialise the
  /// fetched rows.
  final EntityMeta targetMeta;

  const DbSetInclude({
    required this.name,
    required this.targetMeta,
  });
}
