//: `EntityMeta` aggregates all the
// per-entity metadata (columns, embedded fields,
// inheritance, conflict resolution). It is
// constructed by the codegen and read by the runtime;
// the runtime never constructs one itself.
//
// Helper types live in their own files:
// - `OnDeleteAction` → on_delete_action.dart
// - `InheritanceStrategy` → inheritance_strategy.dart
// - `ColumnMeta` + `fkClause` → column_meta.dart
// - `EmbeddedMeta` + `embedColumns` → embedded_meta.dart
// - `ConflictResolver` → sync/conflict_resolver.dart

import '../sync/conflict_resolver.dart' as sync show ConflictResolver;

import 'column_meta.dart';
import 'embedded_meta.dart';
import 'inheritance_strategy.dart';
import 'navigation_meta.dart';

/// Metadata for a single `@Table` entity.
///
/// One `EntityMeta` per entity class. Stored on the
/// class as a `static EntityMeta entityMeta` (emitted
/// by the codegen) and also registered in the global
/// `EntityRegistry` (also by the codegen, via
/// `register<X>EntityMeta` in `initializeD`).
class EntityMeta {
  final String tableName;
  final List<ColumnMeta> columns;
  final List<ColumnMeta> insertableColumns;
  final List<ColumnMeta> updatableColumns;
  final ColumnMeta primaryKey;
  final int primaryKeyIndex;
  final Object? Function(Object) pkOf;
  final Object? Function(Object, ColumnMeta)? readColumn;
  final Object Function(Map<String, Object?>)? fromRow;
  final void Function(Object, Object)? setId;
  final List<EmbeddedMeta> embeddedFields;
  final InheritanceStrategy inheritanceStrategy;
  final EntityMeta? parentMeta;
  final ColumnMeta? discriminatorColumn;
  final String? discriminatorValue;
  final Map<String, EntityMeta>? subclassMetas;
  final String? parentTable;
  final ColumnMeta? joinedFkColumn;
  final bool isAbstract;
  final sync.ConflictResolver? conflictResolver;

  /// .a: the list of navigation properties
  /// for this entity. One [NavigationMeta] per
  /// `@ForeignKey(...)` field (or per reverse-FK
  /// discovered for 1:many relations).
  ///
  /// Empty for entities with no FKs. The codegen
  /// populates this list when constructing the
  /// [EntityMeta] literal.
  final List<NavigationMeta> navigations;

  List<ColumnMeta> get allColumns {
    final List<ColumnMeta> out = <ColumnMeta>[
      ...columns,
      for (final EmbeddedMeta em in embeddedFields) ...em.columns,
    ];
    if (inheritanceStrategy == InheritanceStrategy.tph) {
      for (final EntityMeta child
          in subclassMetas?.values ?? const <EntityMeta>[]) {
        for (final ColumnMeta c in child.columns) {
          if (!out.contains(c)) out.add(c);
        }
      }
    }
    return out;
  }

  List<ColumnMeta> get effectiveInsertableColumns {
    if (inheritanceStrategy != InheritanceStrategy.tph) {
      return insertableColumns;
    }
    return <ColumnMeta>[
      for (final ColumnMeta c in allColumns)
        if (c.sqlName != primaryKey.sqlName) c,
    ];
  }

  List<ColumnMeta> get effectiveUpdatableColumns {
    if (inheritanceStrategy != InheritanceStrategy.tph) {
      return updatableColumns;
    }
    return <ColumnMeta>[
      for (final ColumnMeta c in allColumns)
        if (c.sqlName != primaryKey.sqlName) c,
    ];
  }

  String sqlColumnName(ColumnMeta c) {
    for (final EmbeddedMeta em in embeddedFields) {
      if (em.columns.contains(c)) return em.sqlName(c);
    }
    return c.sqlName;
  }

  const EntityMeta({
    required this.tableName,
    required this.columns,
    required this.insertableColumns,
    required this.updatableColumns,
    required this.primaryKey,
    required this.primaryKeyIndex,
    required this.pkOf,
    this.readColumn,
    this.fromRow,
    this.setId,
    this.embeddedFields = const <EmbeddedMeta>[],
    this.inheritanceStrategy = InheritanceStrategy.none,
    this.parentMeta,
    this.discriminatorColumn,
    this.discriminatorValue,
    this.subclassMetas,
    this.parentTable,
    this.joinedFkColumn,
    this.isAbstract = false,
    this.conflictResolver,
    this.navigations = const <NavigationMeta>[],
  });

  EntityMeta resolveForDiscriminator(Object? value) {
    if (inheritanceStrategy != InheritanceStrategy.tph) return this;
    if (value == null) return this;
    final String key = value.toString();
    final EntityMeta? child = subclassMetas?[key];
    if (child == null) {
      throw StateError(
        'TPH discriminator value "$key" is not registered '
        'on $tableName. Known values: '
        '${subclassMetas?.keys.toList() ?? const <String>[]}.',
      );
    }
    return child;
  }

  EntityMeta copyWith({
    InheritanceStrategy? inheritanceStrategy,
    EntityMeta? parentMeta,
    ColumnMeta? discriminatorColumn,
    String? discriminatorValue,
    Map<String, EntityMeta>? subclassMetas,
    String? parentTable,
    ColumnMeta? joinedFkColumn,
    bool? isAbstract,
  }) {
    return EntityMeta(
      tableName: tableName,
      columns: columns,
      insertableColumns: insertableColumns,
      updatableColumns: updatableColumns,
      primaryKey: primaryKey,
      primaryKeyIndex: primaryKeyIndex,
      pkOf: pkOf,
      readColumn: readColumn,
      fromRow: fromRow,
      setId: setId,
      embeddedFields: embeddedFields,
      inheritanceStrategy: inheritanceStrategy ?? this.inheritanceStrategy,
      parentMeta: parentMeta ?? this.parentMeta,
      discriminatorColumn: discriminatorColumn ?? this.discriminatorColumn,
      discriminatorValue: discriminatorValue ?? this.discriminatorValue,
      subclassMetas: subclassMetas ?? this.subclassMetas,
      parentTable: parentTable ?? this.parentTable,
      joinedFkColumn: joinedFkColumn ?? this.joinedFkColumn,
      isAbstract: isAbstract ?? this.isAbstract,
    );
  }

  String createTableDdl() {
    final StringBuffer buf = StringBuffer()
      ..writeln('CREATE TABLE IF NOT EXISTS $tableName (');
    final List<String> parts = <String>[];
    for (final ColumnMeta c in columns) {
      parts.add(_columnDdl(c));
    }
    for (final EmbeddedMeta em in embeddedFields) {
      parts.add(embedColumns(em));
    }
    buf.writeln('  ${parts.join(',\n  ')}');
    buf.writeln(')');
    return buf.toString();
  }

  List<String> createIndexStatements() {
    final List<String> out = <String>[];
    for (final ColumnMeta c in columns) {
      if (!c.isIndexed) continue;
      final String indexName = c.indexName ?? '${tableName}_${c.sqlName}_idx';
      final String unique = c.isUniqueIndex ? 'UNIQUE ' : '';
      out.add('CREATE ${unique}INDEX $indexName '
          'ON $tableName (${c.sqlName})');
    }
    return out;
  }

  String createFullSchemaDdl() {
    final StringBuffer buf = StringBuffer()..writeln(createTableDdl());
    for (final String idx in createIndexStatements()) {
      buf.writeln(';');
      buf.writeln(idx);
    }
    return buf.toString();
  }

  static String _columnDdl(ColumnMeta c) {
    final StringBuffer buf = StringBuffer()..write('${c.sqlName} ');
    if (c.isPrimaryKey) {
      buf.write('INTEGER PRIMARY KEY');
      if (c.isAutoIncrement) {
        buf.write(' AUTOINCREMENT');
      }
    } else {
      buf.write(_sqliteType(c.dartType));
      if (!c.nullable) {
        buf.write(' NOT NULL');
      }
      if (c.defaultLiteral != null) {
        buf.write(' DEFAULT ${c.defaultLiteral}');
      }
      if (c.isForeignKey && c.foreignTable != null && c.foreignColumn != null) {
        buf.write(' REFERENCES ${c.foreignTable}(${c.foreignColumn})');
      }
    }
    return buf.toString();
  }

  static String _sqliteType(Type t) {
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
}
