// Tests for the SchemaSnapshot types and the
// computeSnapshot function (commit 1 of
// feat/auto-migrations).

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

ColumnMeta _idCol() => ColumnMeta(
      sqlName: 'id',
      dartField: 'id',
      dartType: int,
      isPrimaryKey: true,
      isAutoIncrement: true,
    );

ColumnMeta _nameCol({bool nullable = false}) => ColumnMeta(
      sqlName: 'name',
      dartField: 'name',
      dartType: String,
      nullable: nullable,
    );

ColumnMeta _ageCol({String? defaultLiteral}) => ColumnMeta(
      sqlName: 'age',
      dartField: 'age',
      dartType: int,
      defaultLiteral: defaultLiteral,
    );

ColumnMeta _emailCol({bool isIndexed = false, bool isUniqueIndex = false}) =>
    ColumnMeta(
      sqlName: 'email',
      dartField: 'email',
      dartType: String,
      isIndexed: isIndexed,
      isUniqueIndex: isUniqueIndex,
    );

ColumnMeta _authorIdCol({bool isForeignKey = true}) => ColumnMeta(
      sqlName: 'author_id',
      dartField: 'authorId',
      dartType: int,
      isForeignKey: isForeignKey,
      foreignTable: 'authors',
      foreignColumn: 'id',
    );

EntityMeta _bookMeta({
  List<ColumnMeta>? extraColumns,
  List<EmbeddedMeta>? embeddedFields,
}) {
  final List<ColumnMeta> cols = <ColumnMeta>[
    _idCol(),
    _nameCol(),
    _authorIdCol(),
    if (extraColumns != null) ...extraColumns,
  ];
  return EntityMeta(
    tableName: 'books',
    columns: cols,
    insertableColumns: cols.sublist(1),
    updatableColumns: cols.sublist(1),
    primaryKey: cols[0],
    primaryKeyIndex: 0,
    pkOf: (Object e) => 0,
    embeddedFields: embeddedFields ?? const <EmbeddedMeta>[],
  );
}

void main() {
  group('SchemaSnapshot', () {
    test('toJson / fromJson round-trip preserves the snapshot', () {
      final SchemaSnapshot snap = computeSnapshot(<EntityMeta>[
        _bookMeta(),
      ]);
      final Map<String, Object?> json = snap.toJson();
      final SchemaSnapshot decoded = SchemaSnapshot.fromJson(json);
      expect(decoded.version, snap.version);
      expect(decoded.tables, hasLength(1));
      expect(decoded.tables[0].name, 'books');
      expect(decoded.tables[0].columns, hasLength(3));
    });

    test('encode / decode round-trip via JSON', () {
      final SchemaSnapshot snap = computeSnapshot(<EntityMeta>[
        _bookMeta(),
      ]);
      final String encoded = snap.encode();
      final SchemaSnapshot decoded = SchemaSnapshot.decode(encoded);
      expect(decoded.tables[0].name, 'books');
      expect(decoded.tables[0].columns[1].name, 'name');
      expect(decoded.tables[0].columns[1].sqliteType, 'TEXT');
    });

    test('computeSnapshot is deterministic (same input, same output)', () {
      final SchemaSnapshot a = computeSnapshot(<EntityMeta>[
        _bookMeta(),
      ]);
      final SchemaSnapshot b = computeSnapshot(<EntityMeta>[
        _bookMeta(),
      ]);
      expect(a.encode(), b.encode());
    });

    test('columns are captured with type, nullable, default, FK metadata', () {
      final SchemaSnapshot snap = computeSnapshot(<EntityMeta>[
        _bookMeta(
          extraColumns: <ColumnMeta>[
            _ageCol(defaultLiteral: '0'),
          ],
        ),
      ]);
      final SchemaTable t = snap.tables[0];
      // id: PK auto-increment
      expect(t.columns[0].name, 'id');
      expect(t.columns[0].isPrimaryKey, isTrue);
      expect(t.columns[0].isAutoIncrement, isTrue);
      expect(t.columns[0].sqliteType, 'INTEGER');
      // name: not null
      expect(t.columns[1].name, 'name');
      expect(t.columns[1].nullable, isFalse);
      expect(t.columns[1].sqliteType, 'TEXT');
      // author_id: FK
      final SchemaColumn authorId = t.columns[2];
      expect(authorId.foreignKey, isNotNull);
      expect(authorId.foreignKey!.table, 'authors');
      expect(authorId.foreignKey!.column, 'id');
      // age: default literal
      final SchemaColumn age = t.columns[3];
      expect(age.defaultLiteral, '0');
    });

    test('indexes are captured separately from column metadata', () {
      final SchemaSnapshot snap = computeSnapshot(<EntityMeta>[
        _bookMeta(
          extraColumns: <ColumnMeta>[
            _emailCol(isIndexed: true, isUniqueIndex: true),
          ],
        ),
      ]);
      final SchemaTable t = snap.tables[0];
      expect(t.indexes, hasLength(1));
      expect(t.indexes[0].isUnique, isTrue);
      expect(t.indexes[0].columns, <String>['email']);
      // Index name follows the books_email_unq heuristic.
      expect(t.indexes[0].name, 'books_email_unq');
    });

    test('table with no entities yields an empty (but valid) snapshot', () {
      final SchemaSnapshot snap = computeSnapshot(<EntityMeta>[]);
      expect(snap.tables, isEmpty);
      expect(snap.version, SchemaSnapshot.currentVersion);
    });
  });
}
