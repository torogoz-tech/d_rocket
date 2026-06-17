// Schema snapshot types for the auto-migration system.
//
// A [SchemaSnapshot] is a serializable representation
// of the entire database schema, derived from the
// codegen-emitted [EntityMeta]s. The auto-migrator
// stores the last applied snapshot in the
// `d_rocket_schema_state` table and compares it to
// the current snapshot on each `Db.open` to compute
// the diff.
//
// The snapshot is fully self-contained: it includes
// tables, columns, indexes, primary keys, foreign
// keys, and embedded fields. A TPH (Table-Per-
// Hierarchy) inheritance strategy flattens all
// subclass columns into the parent table; the
// snapshot reflects that flattened shape so the
// diff sees only what SQLite actually stores.

import 'dart:convert';

import '../column_meta.dart';
import '../embedded_meta.dart';
import '../entity_meta.dart';
import '../inheritance_strategy.dart';
import '../on_delete_action.dart';

///: a serializable snapshot of the
/// database schema. Produced by [computeSnapshot]
/// from a list of [EntityMeta] and consumed by
/// the diff algorithm.
///
/// The snapshot is JSON-friendly: a list of
/// [SchemaTable]s plus a version string. The
/// version is bumped on every shape change to
/// the snapshot itself (so a 1.2.0 snapshot can
/// be detected as such by an older 1.1.x runtime
/// that does not yet know the new shape).
class SchemaSnapshot {
  ///: bump on every shape change to
  /// the snapshot itself. A 1.1.x runtime that
  /// finds a 1.2.0 snapshot in the table can
  /// refuse to migrate ("snapshot is from a
  /// newer d_rocket; upgrade to proceed").
  static const int currentVersion = 1;

  final int version;
  final List<SchemaTable> tables;

  const SchemaSnapshot({
    required this.version,
    required this.tables,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'version': version,
        'tables': <Map<String, Object?>>[
          for (final SchemaTable t in tables) t.toJson(),
        ],
      };

  String encode() => jsonEncode(toJson());

  static SchemaSnapshot fromJson(Map<String, Object?> json) {
    final int v = (json['version'] as int?) ?? 1;
    final List<Object?> rawTables = (json['tables'] as List<Object?>?) ??
        const <Object?>[];
    return SchemaSnapshot(
      version: v,
      tables: <SchemaTable>[
        for (final Object? t in rawTables)
          SchemaTable.fromJson(t! as Map<String, Object?>),
      ],
    );
  }

  static SchemaSnapshot decode(String encoded) =>
      fromJson(jsonDecode(encoded) as Map<String, Object?>);

  /// Lookup by table name. Returns `null` if absent.
  SchemaTable? table(String name) {
    for (final SchemaTable t in tables) {
      if (t.name == name) return t;
    }
    return null;
  }

  @override
  String toString() => 'SchemaSnapshot(v$version, '
      '${tables.length} table${tables.length == 1 ? "" : "s"})';
}

///: a single table in the snapshot,
/// including its columns and indexes.
class SchemaTable {
  final String name;
  final List<SchemaColumn> columns;
  final List<SchemaIndex> indexes;

  /// Names of the primary-key columns. Empty for
  /// tables without a primary key. SQLite supports
  /// composite primary keys; we capture the full
  /// set so the diff can detect a change in the
  /// PK shape.
  final List<String> primaryKey;

  const SchemaTable({
    required this.name,
    required this.columns,
    required this.indexes,
    required this.primaryKey,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'columns': <Map<String, Object?>>[
          for (final SchemaColumn c in columns) c.toJson(),
        ],
        'indexes': <Map<String, Object?>>[
          for (final SchemaIndex i in indexes) i.toJson(),
        ],
        'primaryKey': primaryKey,
      };

  static SchemaTable fromJson(Map<String, Object?> json) {
    final List<Object?> rawCols =
        (json['columns'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> rawIdx =
        (json['indexes'] as List<Object?>?) ?? const <Object?>[];
    final List<Object?> rawPk =
        (json['primaryKey'] as List<Object?>?) ?? const <Object?>[];
    return SchemaTable(
      name: json['name']! as String,
      columns: <SchemaColumn>[
        for (final Object? c in rawCols)
          SchemaColumn.fromJson(c! as Map<String, Object?>),
      ],
      indexes: <SchemaIndex>[
        for (final Object? i in rawIdx)
          SchemaIndex.fromJson(i! as Map<String, Object?>),
      ],
      primaryKey: <String>[for (final Object? p in rawPk) p! as String],
    );
  }

  SchemaColumn? column(String name) {
    for (final SchemaColumn c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }

  SchemaIndex? indexNamed(String name) {
    for (final SchemaIndex i in indexes) {
      if (i.name == name) return i;
    }
    return null;
  }

  @override
  String toString() => 'SchemaTable($name, '
      '${columns.length} cols, ${indexes.length} indexes)';
}

///: a single column in the snapshot.
/// Mirrors the relevant fields of [ColumnMeta]
/// but in a JSON-friendly form.
class SchemaColumn {
  final String name;

  /// Canonical SQLite type for the Dart type
  /// (`INTEGER`, `TEXT`, `REAL`, …). Captured at
  /// snapshot time so a later change to the type
  /// mapper is visible in the diff.
  final String sqliteType;

  final bool nullable;
  final String? defaultLiteral;
  final bool isPrimaryKey;
  final bool isAutoIncrement;

  /// Foreign-key metadata. `null` for non-FK
  /// columns.
  final SchemaForeignKey? foreignKey;

  const SchemaColumn({
    required this.name,
    required this.sqliteType,
    required this.nullable,
    this.defaultLiteral,
    this.isPrimaryKey = false,
    this.isAutoIncrement = false,
    this.foreignKey,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'sqliteType': sqliteType,
        'nullable': nullable,
        'defaultLiteral': defaultLiteral,
        'isPrimaryKey': isPrimaryKey,
        'isAutoIncrement': isAutoIncrement,
        'foreignKey': foreignKey?.toJson(),
      };

  static SchemaColumn fromJson(Map<String, Object?> json) {
    return SchemaColumn(
      name: json['name']! as String,
      sqliteType: json['sqliteType']! as String,
      nullable: (json['nullable'] as bool?) ?? false,
      defaultLiteral: json['defaultLiteral'] as String?,
      isPrimaryKey: (json['isPrimaryKey'] as bool?) ?? false,
      isAutoIncrement: (json['isAutoIncrement'] as bool?) ?? false,
      foreignKey: json['foreignKey'] == null
          ? null
          : SchemaForeignKey.fromJson(
              json['foreignKey']! as Map<String, Object?>),
    );
  }

  @override
  String toString() => 'SchemaColumn($name: $sqliteType'
      '${nullable ? "" : " NOT NULL"}'
      '${defaultLiteral != null ? " DEFAULT $defaultLiteral" : ""}'
      '${foreignKey != null ? " FK→${foreignKey!.table}.${foreignKey!.column}" : ""}'
      ')';
}

///: foreign-key target (used inside
/// [SchemaColumn]).
class SchemaForeignKey {
  final String table;
  final String column;
  final OnDeleteAction onDelete;

  const SchemaForeignKey({
    required this.table,
    required this.column,
    this.onDelete = OnDeleteAction.noAction,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'table': table,
        'column': column,
        'onDelete': onDelete.name,
      };

  static SchemaForeignKey fromJson(Map<String, Object?> json) {
    final String onDeleteName =
        (json['onDelete'] as String?) ?? OnDeleteAction.noAction.name;
    return SchemaForeignKey(
      table: json['table']! as String,
      column: json['column']! as String,
      onDelete: OnDeleteAction.values.firstWhere(
        (OnDeleteAction a) => a.name == onDeleteName,
        orElse: () => OnDeleteAction.noAction,
      ),
    );
  }
}

///: a single index in the snapshot.
class SchemaIndex {
  final String name;
  final List<String> columns;
  final bool isUnique;

  const SchemaIndex({
    required this.name,
    required this.columns,
    this.isUnique = false,
  });

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'columns': columns,
        'isUnique': isUnique,
      };

  static SchemaIndex fromJson(Map<String, Object?> json) {
    final List<Object?> rawCols =
        (json['columns'] as List<Object?>?) ?? const <Object?>[];
    return SchemaIndex(
      name: json['name']! as String,
      columns: <String>[for (final Object? c in rawCols) c! as String],
      isUnique: (json['isUnique'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'SchemaIndex($name: '
      '${isUnique ? "UNIQUE" : ""}'
      '(${columns.join(", ")}))';
}

///: convert the canonical SQLite type
/// for a Dart [Type]. Same mapping as
/// [EntityMeta._sqliteType] (private there, so
/// duplicated here — they MUST stay in sync).
String sqliteTypeFor(Type t) {
  if (t == int) return 'INTEGER';
  if (t == double) return 'REAL';
  if (t == num) return 'NUMERIC';
  if (t == bool) return 'INTEGER';
  if (t == String) return 'TEXT';
  if (t == DateTime) return 'TEXT';
  if (t == BigInt) return 'INTEGER';
  if (t == Duration) return 'INTEGER';
  return 'TEXT';
}

///: convert a [ColumnMeta] to a
/// [SchemaColumn]. The conversion is
/// deterministic (same input → same output).
SchemaColumn columnToSnapshot(
  ColumnMeta c, {
  String? nameOverride,
}) {
  return SchemaColumn(
    name: nameOverride ?? c.sqlName,
    sqliteType: sqliteTypeFor(c.dartType),
    nullable: c.nullable,
    defaultLiteral: c.defaultLiteral,
    isPrimaryKey: c.isPrimaryKey,
    isAutoIncrement: c.isAutoIncrement,
    foreignKey: c.isForeignKey &&
            c.foreignTable != null &&
            c.foreignColumn != null
        ? SchemaForeignKey(
            table: c.foreignTable!,
            column: c.foreignColumn!,
            onDelete: c.onDelete,
          )
        : null,
  );
}

///: derive the index name for a
/// [ColumnMeta] that has `isIndexed: true`. Same
/// heuristic as [EntityMeta.createIndexStatements].
String indexNameFor(SchemaTable table, ColumnMeta c) {
  if (c.indexName != null) return c.indexName!;
  final String suffix = c.isUniqueIndex ? 'unq' : 'idx';
  return '${table.name}_${c.sqlName}_$suffix';
}

///: produce a [SchemaSnapshot] from a
/// list of [EntityMeta]s. The order of tables in
/// the output is the order of the input. TPH
/// subclass columns are flattened into the parent
/// table (matching the on-disk shape).
SchemaSnapshot computeSnapshot(List<EntityMeta> metas) {
  final List<SchemaTable> tables = <SchemaTable>[];
  for (final EntityMeta meta in metas) {
    if (meta.isAbstract) {
      // Abstract entities (e.g. the base of a TPH
      // hierarchy) do not have a table; their
      // columns are flattened into a concrete
      // subclass. Skip.
      continue;
    }
    if (meta.inheritanceStrategy == InheritanceStrategy.tph) {
      _appendTphTable(tables, meta);
    } else {
      _appendConcreteTable(tables, meta);
    }
  }
  return SchemaSnapshot(
    version: SchemaSnapshot.currentVersion,
    tables: tables,
  );
}

void _appendConcreteTable(
  List<SchemaTable> tables,
  EntityMeta meta,
) {
  final List<SchemaColumn> cols = <SchemaColumn>[
    for (final ColumnMeta c in meta.columns) columnToSnapshot(c),
  ];
  for (final EmbeddedMeta em in meta.embeddedFields) {
    for (final ColumnMeta c in em.columns) {
      cols.add(columnToSnapshot(c, nameOverride: em.sqlName(c)));
    }
  }
  final List<String> pk = meta.primaryKey.sqlName.isEmpty
      ? const <String>[]
      : <String>[meta.primaryKey.sqlName];
  final List<SchemaIndex> indexes = <SchemaIndex>[];
  for (final ColumnMeta c in meta.columns) {
    if (!c.isIndexed) continue;
    indexes.add(
      SchemaIndex(
        name: indexNameFor(
          SchemaTable(
            name: meta.tableName,
            columns: cols,
            indexes: const <SchemaIndex>[],
            primaryKey: pk,
          ),
          c,
        ),
        columns: <String>[c.sqlName],
        isUnique: c.isUniqueIndex,
      ),
    );
  }
  tables.add(
    SchemaTable(
      name: meta.tableName,
      columns: cols,
      indexes: indexes,
      primaryKey: pk,
    ),
  );
}

void _appendTphTable(List<SchemaTable> tables, EntityMeta root) {
  // The on-disk shape of a TPH hierarchy is a
  // single table whose columns are the union of
  // the root's columns and every concrete
  // subclass's columns. The discriminator column
  // is also a column. We flatten the whole tree
  // into one [SchemaTable].
  final List<SchemaColumn> cols = <SchemaColumn>[
    for (final ColumnMeta c in root.columns) columnToSnapshot(c),
  ];
  for (final EmbeddedMeta em in root.embeddedFields) {
    for (final ColumnMeta c in em.columns) {
      cols.add(columnToSnapshot(c, nameOverride: em.sqlName(c)));
    }
  }
  final Map<String, EntityMeta>? children = root.subclassMetas;
  if (children != null) {
    for (final EntityMeta child in children.values) {
      for (final ColumnMeta c in child.columns) {
        // De-dupe: a subclass might override a
        // root column with a different type, in
        // which case the subclass version wins.
        if (!cols.any((SchemaColumn sc) => sc.name == c.sqlName)) {
          cols.add(columnToSnapshot(c));
        }
      }
    }
  }
  final List<String> pk = root.primaryKey.sqlName.isEmpty
      ? const <String>[]
      : <String>[root.primaryKey.sqlName];
  // For TPH, collect indexes from the root and
  // every concrete subclass.
  final List<SchemaIndex> indexes = <SchemaIndex>[];
  for (final ColumnMeta c in root.columns) {
    if (!c.isIndexed) continue;
    indexes.add(
      SchemaIndex(
        name: indexNameFor(
          SchemaTable(
            name: root.tableName,
            columns: cols,
            indexes: const <SchemaIndex>[],
            primaryKey: pk,
          ),
          c,
        ),
        columns: <String>[c.sqlName],
        isUnique: c.isUniqueIndex,
      ),
    );
  }
  if (children != null) {
    for (final EntityMeta child in children.values) {
      for (final ColumnMeta c in child.columns) {
        if (!c.isIndexed) continue;
        if (indexes.any((SchemaIndex i) => i.name == c.indexName)) continue;
        indexes.add(
          SchemaIndex(
            name: indexNameFor(
              SchemaTable(
                name: root.tableName,
                columns: cols,
                indexes: const <SchemaIndex>[],
                primaryKey: pk,
              ),
              c,
            ),
            columns: <String>[c.sqlName],
            isUnique: c.isUniqueIndex,
          ),
        );
      }
    }
  }
  tables.add(
    SchemaTable(
      name: root.tableName,
      columns: cols,
      indexes: indexes,
      primaryKey: pk,
    ),
  );
}
