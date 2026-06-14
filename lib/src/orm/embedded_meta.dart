import 'column_meta.dart';

/// Metadata for a single `@Embedded` value object
/// (EF Core's `OwnsOne` / `ComplexProperty` pattern).
/// The fields of the embedded type are flattened into
/// the parent table — they don't get their own table
/// and they don't carry an FK.
///
/// MVP scope: only single-instance embedding
/// (i.e. `OwnsOne` / `ComplexProperty`, not `OwnsMany`
/// / `ComplexCollection`).
class EmbeddedMeta {
  /// Name of the field on the parent (e.g. `'address'`).
  final String name;

  /// Dart runtime type of the embedded object.
  final Type dartType;

  /// Columns flattened into the parent table. The SQL
  /// names are taken as-is (or prefixed, see [prefix]).
  final List<ColumnMeta> columns;

  /// Optional prefix to apply to the embedded SQL
  /// column names (e.g. `'addr'` → `addr_street`,
  /// `addr_city`). If `null` (the default), the
  /// columns are emitted as-is.
  final String? prefix;

  /// Factory that constructs the embedded object from
  /// a raw row map.
  final Object Function(Map<String, Object?>) fromRow;

  /// Reads the embedded object from a parent instance.
  final Object? Function(Object) get;

  /// Sets the embedded object on a parent instance.
  final void Function(Object, Object?) set;

  const EmbeddedMeta({
    required this.name,
    required this.dartType,
    required this.columns,
    this.prefix,
    required this.fromRow,
    required this.get,
    required this.set,
  });

  /// Returns the SQL column name for the embedded
  /// [ColumnMeta] (applying [prefix] if set).
  String sqlName(ColumnMeta c) {
    if (prefix == null) return c.sqlName;
    return '${prefix}_${c.sqlName}';
  }
}

/// Emit the comma-separated flattened column list for
/// an [EmbeddedMeta]'s fields, e.g.
/// `'street TEXT NOT NULL, city TEXT NOT NULL'`.
///
/// Compose it into a `CREATE TABLE` statement:
/// ```dart
/// final ddl = 'CREATE TABLE customers (... ${embedColumns(addressMeta)})';
/// ```
String embedColumns(EmbeddedMeta em) {
  final List<String> parts = <String>[];
  for (final ColumnMeta c in em.columns) {
    final StringBuffer buf = StringBuffer()
      ..write('${em.sqlName(c)} ')
      ..write(_sqliteTypeFor(c.dartType));
    if (!c.nullable) buf.write(' NOT NULL');
    if (c.defaultLiteral != null) {
      buf.write(' DEFAULT ${c.defaultLiteral}');
    }
    parts.add(buf.toString());
  }
  return parts.join(', ');
}

/// Maps a Dart runtime type to its canonical SQLite
/// storage type.
String _sqliteTypeFor(Type t) {
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
