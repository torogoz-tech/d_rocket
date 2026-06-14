/// Global registry of `@Table` entities.
///
/// The codegen emits a `register<X>EntityMeta` for every
/// `@Table` class it sees, and `d_rocket_registry.g.dart`'s
/// `initializeD` calls them all. After that, every entity
/// type `T` is resolvable via `EntityRegistry.metaFor<T>`.
///
/// The registry is global on purpose: `DbContext` does
/// not own a separate registry per context, and the per-class
/// `static EntityMeta entityMeta` is the primary source of
/// truth (used by `DbSet<T>`). The global registry exists for
/// the cases where a value-typed lookup is more convenient
/// (e.g. dynamic dispatch from a generic `Object?` value).
library;

import 'entity_meta.dart';

class EntityRegistry {
  EntityRegistry._();

  /// Singleton storage: `Type → EntityMeta`.
  static final Map<Type, EntityMeta> _metas = <Type, EntityMeta>{};

  /// Registers [meta] for the entity type [t]. Called by the
  /// codegen's `register<X>EntityMeta` helper, which in turn
  /// is called from the central `initializeD`.
  static void register<T>(EntityMeta meta) {
    _metas[T] = meta;
  }

  /// Returns the [EntityMeta] for [t], or `null` if [t] is not
  /// a `@Table` class.
  static EntityMeta? tryMetaFor(Type t) => _metas[t];

  /// Returns the [EntityMeta] for [t]. Throws [StateError] if
  /// [t] is not registered. Use [tryMetaFor] when the caller
  /// wants a soft-fail.
  static EntityMeta metaFor(Type t) {
    final EntityMeta? m = _metas[t];
    if (m == null) {
      throw StateError(
        'No @Table metadata registered for $t. '
        'Did you forget to call initializeD()? '
        'Or is $t not annotated with @Table?',
      );
    }
    return m;
  }

  /// Drops every entry. Used by tests for isolation.
  static void reset() {
    _metas.clear();
  }

  /// All currently registered types (for diagnostic logging).
  static Iterable<Type> get registeredTypes => _metas.keys;
}
