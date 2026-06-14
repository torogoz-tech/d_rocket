// .c — `NavigationPopulator`:
//
// A helper that populates a navigation property for a
// list of entities. Fetches the related entities with
// a single batched `WHERE fk IN (?, ?, …)` query (no
// N+1) and writes them into the [NavigationRegistry].
//
// Usage (.c MVP — user calls explicitly):
// ```dart
// final orders = await db.set<Order>.toListAsync_;
// await NavigationPopulator.populate<Customer>(
// entities: orders,
// meta: Order.entityMeta,
// navigationName: 'customer',
// targetMeta: Customer.entityMeta,
// selectFn: (sql, binds) async =>
// db.rawSelect(sql, binds),
//);
//
// // Now the closure sees the populated value:
// final filtered = orders
// .where((o) => o.customer?.name == 'John')
// .toList;
// ```
//
// .e will add `.include_((o) => o.customer)`
// on `DbSet<T>` so the user doesn't have to call this
// manually. For now, the pattern above is the canonical
// way to do it.

import 'dart:async';

import 'column_meta.dart';
import 'entity_meta.dart';
import 'navigation_meta.dart';
import 'navigation_registry.dart';

/// .c: a static helper for populating a
/// navigation property on a list of entities. Fetches
/// the related entities in one batched query and writes
/// them into the [NavigationRegistry].
class NavigationPopulator {
  /// .c: populate the [navigationName]
  /// navigation for all [entities]. The fetch is a
  /// single `SELECT * FROM target WHERE fk IN
  /// (?, ?, …)` query (no N+1).
  ///
  /// - [entities] — the source list. Each entity's
  /// [NavigationMeta.fkColumn] is read to get the
  /// list of FK values.
  /// - [sourceMeta] — the [EntityMeta] for the source
  /// type (used to find the [NavigationMeta] by name).
  /// - [targetMeta] — the [EntityMeta] for the target
  /// type. Used to get the primary key column and
  /// the `fromRow` constructor.
  /// - [selectFn] — a function that executes a raw
  /// `SELECT` and returns the rows. The user plugs
  /// in their db connection here.
  /// - [navigationName] — which navigation to populate
  /// (must match a [NavigationMeta.name] in
  /// [sourceMeta]).
  /// - [targetDartType] — the runtime type of the
  /// target entity (used to cast the row via
  /// `targetMeta.fromRow`).
  ///
  /// Returns the list of related entities that
  /// were fetched (in case the caller wants to use
  /// them directly).
  static Future<List<T>> populate<T>({
    required List<Object> entities,
    required EntityMeta sourceMeta,
    required EntityMeta targetMeta,
    required String navigationName,
    required Future<List<Object?>> Function(String sql, List<Object?> binds)
        selectFn,
  }) async {
    // 1. Find the NavigationMeta.
    final NavigationMeta nav = sourceMeta.navigations.firstWhere(
      (NavigationMeta n) => n.name == navigationName,
      orElse: () => throw StateError(
        'Navigation "$navigationName" not found on '
        '${sourceMeta.tableName}. Available: '
        '${sourceMeta.navigations.map((NavigationMeta n) => n.name).toList()}',
      ),
    );

    // 2. Read the FK values from each source entity.
    final List<Object?> fkValues = <Object?>[
      for (final Object e in entities) _readField(e, nav.fkColumn, sourceMeta)
    ];
    if (fkValues.isEmpty) return <T>[];

    // 3. Build a batched `WHERE fk IN (?, ?, …)` query.
    final String placeholders =
        List<String>.filled(fkValues.length, '?').join(', ');
    final String sql = 'SELECT * FROM ${nav.targetTable} '
        'WHERE ${nav.targetColumn} IN ($placeholders)';
    final List<Object?> rows = await selectFn(sql, fkValues);

    // 4. Materialise the related entities from the
    // raw rows. Uses `targetMeta.fromRow` (set by
    // the codegen). If fromRow is null (e.g., a
    // user-built meta without codegen), we throw
    // — there's no way to materialise the row.
    final Object? Function(Map<String, Object?>)? fromRow = targetMeta.fromRow;
    if (fromRow == null) {
      throw StateError(
        'Target EntityMeta for ${targetMeta.tableName} has no fromRow. '
        'The codegen should set one; this is a builder bug.',
      );
    }
    final List<T> related = <T>[
      for (final Object? row in rows) fromRow(row as Map<String, Object?>) as T
    ];

    // 5. Index the related entities by their PK.
    // For 1:1 navigation, at most one related
    // entity per PK value.
    final Map<Object, T> byPk = <Object, T>{};
    for (int i = 0; i < rows.length; i++) {
      // The PK value is the first column (we
      // assume `*` returns the column order
      // matching the table DDL, which has the PK
      // first).
      // .c MVP: read via the primary
      // key's readColumn. We use the target's
      // `pkOf` if available.
      final Object? pk = targetMeta.pkOf(related[i] as Object);
      byPk[pk as Object] = related[i];
    }

    // 6. Populate the registry: for each source
    // entity, look up the related entity by FK
    // value and write into the registry.
    for (int i = 0; i < entities.length; i++) {
      final Object entity = entities[i];
      final Object? fkValue = fkValues[i];
      if (fkValue == null) continue;
      final T? relatedEntity = byPk[fkValue];
      NavigationRegistry.set<T>(entity, nav.name, relatedEntity);
    }

    return related;
  }

  /// .c helper: read a field value from
  /// an entity via its [EntityMeta]. Uses the meta's
  /// `readColumn` if available, otherwise throws.
  static Object? _readField(
    Object entity,
    String field,
    EntityMeta meta,
  ) {
    final Object? Function(Object, ColumnMeta)? reader = meta.readColumn;
    if (reader == null) {
      throw StateError(
        'EntityMeta for ${meta.tableName} has no readColumn. '
        'The codegen should set one; this is a builder bug.',
      );
    }
    // Find the ColumnMeta for the field.
    final ColumnMeta col = meta.columns.firstWhere(
      (ColumnMeta c) => c.dartField == field,
      orElse: () => throw StateError(
        'Field "$field" not found in ${meta.tableName} columns: '
        '${meta.columns.map((ColumnMeta c) => c.dartField).toList()}',
      ),
    );
    return reader(entity, col);
  }
}
