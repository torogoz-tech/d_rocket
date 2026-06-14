// .b — `NavigationRegistry`:
//
// A per-entity-instance map for navigation properties.
// The codegen emits `Customer? get customer =>
// NavigationRegistry.get<Customer>(this, 'customer');`
// in the entity's navigation extension. The framework
// (e.g. after `.include_((o) => o.customer)`) populates
// the registry with the fetched entity.
//
// Why Expando?
//
// - It holds per-instance state without modifying
// the entity class (the entity doesn't need a
// `_navigations` field).
// - It auto-cleans when the entity is garbage-
// collected (no manual lifecycle).
// - It's safe to access from any context (the
// framework, the closure, the user).
//
// Limitations:
//
// - The Expando's keys are identity-based. Two
// distinct `Order` instances (even with the same
// data) have separate nav slots. That's the
// right semantics for "navigations belong to a
// specific loaded row".
// - The Expando doesn't survive serialization
// (it's a runtime-only construct). For caching
// across requests, use a separate
// `NavigationCache` (.e).
//
// Threading: not thread-safe. The framework
// assumes single-threaded access (typical for a
// request-scoped db session).

import 'navigation_meta.dart';

/// .b: a per-instance map for navigation
/// properties on entities. Used by the codegen-emitted
/// `extension XxxNavigation on Xxx` getters to read
/// the populated values, and by the framework (via
/// `set`) to populate them after a fetch or `.include_`.
class NavigationRegistry {
  /// .b: the per-instance map. Keyed by
  /// the entity object itself (identity). Value is
  /// a map from navigation name to the related
  /// entity (or list, for 1:many).
  static final Expando<Map<String, Object?>> _store =
      Expando<Map<String, Object?>>('d_rocket.NavigationRegistry');

  /// .b: read a navigation value. Returns
  /// `null` if the navigation hasn't been populated.
  ///
  /// The generic [T] is for type safety at the call
  /// site; the runtime cast is unchecked.
  static T? get<T>(Object entity, String name) {
    final Map<String, Object?>? map = _store[entity];
    if (map == null) return null;
    return map[name] as T?;
  }

  /// .b: write a navigation value. Used
  /// by the framework to populate after a fetch or
  /// `.include_`.
  static void set<T>(Object entity, String name, T? value) {
    final Map<String, Object?> map = _store[entity] ??= <String, Object?>{};
    map[name] = value;
  }

  /// .b: clear all navigations for an
  /// entity. Useful for tests and for refresh-after-
  /// update patterns.
  static void clear(Object entity) {
    _store[entity]?.clear();
  }

  /// .b: check if a navigation has been
  /// populated. Returns `true` even if the value is
  /// `null` (which is a valid state — the related
  /// entity was looked up and not found).
  static bool has(Object entity, String name) {
    final Map<String, Object?>? map = _store[entity];
    if (map == null) return false;
    return map.containsKey(name);
  }

  /// .b: get all populated navigations
  /// for an entity. Returns an empty map if none.
  /// Used for diagnostics.
  static Map<String, Object?> all(Object entity) {
    return Map<String, Object?>.from(_store[entity] ?? <String, Object?>{});
  }

  /// .b: bulk-populate navigations for an
  /// entity. Used by the framework after a batched
  /// `.include_` fetch.
  static void setAll(Object entity, Map<String, Object?> values) {
    final Map<String, Object?> map = _store[entity] ??= <String, Object?>{};
    map.addAll(values);
  }

  /// .b: derive a navigation getter name
  /// for a `NavigationMeta`. Currently just returns
  /// `meta.name`; exists as a hook for .b+
  /// (e.g. snake_case → camelCase conversion).
  static String getterName(NavigationMeta meta) => meta.name;
}
