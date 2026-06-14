// Tests for the ORM runtime (Layer 4 of d_rocket).
//
// These cover:
// * `EntityMeta.createTableDdl` produces the expected SQL.
// * `EntityRegistry.register/tryMetaFor/metaFor/reset` work.
// * `ChangeTracker` lifecycle (track/untrack/clear/rekey).
// * `EntityState` enum has the documented 5 values.
// * `DbSet<T>` staging (add/addRange/remove/clearLocalChanges).
// * `DbContext.saveChanges` issues INSERT / UPDATE /
// DELETE in the documented order against a hand-rolled
// `int Function(String, List<Object?>)` provider callback.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  setUp(EntityRegistry.reset);
  tearDown(EntityRegistry.reset);

  group('Fase 3 — ORM runtime: metadata + registry', () {
    test(
        'EntityMeta.createTableDdl emits a CREATE TABLE with the right '
        'columns, types, and NOT NULL constraints', () {
      final EntityMeta meta = _authorMeta();
      final String ddl = meta.createTableDdl();
      expect(ddl, startsWith('CREATE TABLE IF NOT EXISTS authors ('));
      expect(ddl, contains("id INTEGER PRIMARY KEY AUTOINCREMENT"));
      expect(ddl, contains("name TEXT NOT NULL"));
      expect(ddl, contains("country TEXT NOT NULL"));
    });

    test('EntityMeta.createTableDdl respects nullable and defaultValue', () {
      final EntityMeta meta = _nullableMeta();
      final String ddl = meta.createTableDdl();
      expect(ddl, contains('description TEXT'));
      expect(ddl, isNot(contains('description TEXT NOT NULL')),
          reason: 'nullable:true should suppress NOT NULL');
      expect(ddl, contains('rating INTEGER NOT NULL DEFAULT 0'));
    });

    test('EntityMeta.createTableDdl emits REFERENCES for FK columns (Fase 3.6)',
        () {
      final EntityMeta meta = _bookMeta();
      final String ddl = meta.createTableDdl();
      expect(ddl, contains('author_id INTEGER NOT NULL REFERENCES authors(id)'),
          reason: 'Fase 3.6: @ForeignKey emits REFERENCES in DDL');
    });

    test('EntityMeta.createIndexStatements emits CREATE INDEX (Fase 3.6)', () {
      final EntityMeta meta = _bookMeta();
      final List<String> idxs = meta.createIndexStatements();
      // `_bookMeta` declares one unique index on `isbn`.
      // The output is `CREATE UNIQUE INDEX …` (note the
      // keyword "INDEX" is always present, but the prefix
      // differs between unique and non-unique).
      expect(idxs, hasLength(1));
      expect(idxs.first, contains('INDEX'));
      expect(idxs.first, contains('books'));
      // The unique marker is present:
      expect(idxs.first, contains('UNIQUE'));
      // The custom index name from `@Index(name: ...)` is
      // respected:
      expect(idxs.first, contains('books_isbn_unq'));
    });

    test(
        'EntityMeta.createFullSchemaDdl = CREATE TABLE + CREATE INDEX '
        'in one call (Fase 3.6)', () {
      final EntityMeta meta = _bookMeta();
      final String full = meta.createFullSchemaDdl();
      expect(full, contains('CREATE TABLE IF NOT EXISTS books'));
      expect(full, contains('CREATE '));
      expect(full, contains('INDEX'));
      expect(full, contains('REFERENCES authors(id)'));
    });

    test('EntityRegistry.register + metaFor round-trips', () {
      final EntityMeta meta = _authorMeta();
      EntityRegistry.register<Author>(meta);
      expect(EntityRegistry.metaFor(Author), same(meta));
      expect(EntityRegistry.tryMetaFor(Author), same(meta));
    });

    test('EntityRegistry.metaFor throws on unknown type', () {
      expect(() => EntityRegistry.metaFor(_Unknown), throwsStateError);
    });

    test('EntityRegistry.reset drops every entry', () {
      EntityRegistry.register<Author>(_authorMeta());
      EntityRegistry.reset();
      expect(EntityRegistry.tryMetaFor(Author), isNull);
    });
  });

  group('Fase 3.5 — ORM runtime: @ForeignKey and @Index metadata', () {
    test('ColumnMeta surfaces isForeignKey, foreignTable, foreignColumn', () {
      // The codegen produces a ColumnMeta with these fields
      // when the field is annotated with `@ForeignKey(...)`
      // or `@Column(isForeignKey: true, ...)`. The MVP
      // does not enforce FK constraints at the
      // SQL level; this is metadata for downstream tools.
      const ColumnMeta fk = ColumnMeta(
        sqlName: 'author_id',
        dartField: 'authorId',
        dartType: int,
        isForeignKey: true,
        foreignTable: 'authors',
        foreignColumn: 'id',
      );
      expect(fk.isForeignKey, isTrue);
      expect(fk.foreignTable, 'authors');
      expect(fk.foreignColumn, 'id');
    });

    test('ColumnMeta surfaces isIndexed and isUniqueIndex', () {
      const ColumnMeta idx = ColumnMeta(
        sqlName: 'email',
        dartField: 'email',
        dartType: String,
        isIndexed: true,
        isUniqueIndex: true,
      );
      expect(idx.isIndexed, isTrue);
      expect(idx.isUniqueIndex, isTrue);

      const ColumnMeta noIdx = ColumnMeta(
        sqlName: 'description',
        dartField: 'description',
        dartType: String,
      );
      expect(noIdx.isIndexed, isFalse);
      expect(noIdx.isUniqueIndex, isFalse);
    });

    test('@ForeignKey annotation carries table and column reference', () {
      // Annotation-level: the user can write either
      // `@ForeignKey(table: 'authors', column: 'id')` (clean)
      // or `@Column(isForeignKey: true, ...)` (verbose). The
      // codegen normalises both into the same ColumnMeta
      // shape.
      const ForeignKey fk = ForeignKey(
        table: 'authors',
        column: 'id',
        name: 'author_id',
      );
      expect(fk.isForeignKey, isTrue);
      expect(fk.table, 'authors');
      expect(fk.column, 'id');
      expect(fk.name, 'author_id');
    });

    test('@Index annotation carries unique and name', () {
      const Index plain = Index();
      const Index uniq = Index(unique: true, name: 'books_isbn_unq');
      expect(plain.unique, isFalse);
      expect(plain.name, isNull);
      expect(uniq.unique, isTrue);
      expect(uniq.name, 'books_isbn_unq');
    });
  });

  group('Fase 3 — ORM runtime: change tracking', () {
    test('EntityState enum has 5 values in the documented order', () {
      expect(EntityState.values, <EntityState>[
        EntityState.detached,
        EntityState.added,
        EntityState.unchanged,
        EntityState.modified,
        EntityState.removed,
      ]);
    });

    test('ChangeTracker.track + entries', () {
      final ChangeTracker t = ChangeTracker();
      final Author a = Author(id: 1, name: 'Le Guin', country: 'USA');
      t.track(a, EntityState.added);
      expect(t.length, 1);
      expect(t.entries.single.entity, same(a));
      expect(t.entries.single.state, EntityState.added);
    });

    test('ChangeTracker.untrack removes the entry', () {
      final ChangeTracker t = ChangeTracker();
      final Author a = Author(id: 1, name: 'X', country: 'USA');
      t.track(a, EntityState.added);
      // The MVP tracker keys entries by `identityHashCode`
      // until a real PK is known, so we look up by the same
      // identity key.
      final String key = '<pending:${identityHashCode(a)}>';
      expect(t[key], isNotNull);
      expect(t.untrack(key), isTrue);
      expect(t.length, 0);
    });

    test('ChangeTracker.clear drops every entry', () {
      final ChangeTracker t = ChangeTracker();
      t.track(Author(id: 1, name: 'A', country: 'B'), EntityState.added);
      t.track(Author(id: 2, name: 'C', country: 'D'), EntityState.modified);
      t.clear();
      expect(t.length, 0);
    });

    test('ChangeTracker.rekey moves an entry from one key to another', () {
      final ChangeTracker t = ChangeTracker();
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      t.track(a, EntityState.added);
      final String oldKey = '<pending:${identityHashCode(a)}>';
      t.rekey(oldKey, 1);
      expect(t[oldKey], isNull);
      expect(t[1], isNotNull);
      expect(t[1]!.entity, same(a));
    });
  });

  group('Fase 3 — ORM runtime: DbSet staging + SaveChanges', () {
    test('DbSet.add stages a single entity in the tracker', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      ctx.authors.add(a);
      expect(ctx.changeTracker.length, 1);
      expect(ctx.changeTracker.entries.single.state, EntityState.added);
    });

    test('DbSet.addRange stages every entity in the iterable', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      ctx.authors.addRange(<Author>[
        Author(id: 1, name: 'A', country: 'X'),
        Author(id: 2, name: 'B', country: 'Y'),
      ]);
      expect(ctx.changeTracker.length, 2);
    });

    test('DbSet.remove stages a single entity as Removed', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      ctx.authors.remove(a);
      expect(ctx.changeTracker.entries.single.state, EntityState.removed);
    });

    test(
        'SaveChanges issues INSERT for Added, UPDATE for Modified, '
        'DELETE for Removed — in that order', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);

      ctx.authors.add(Author(id: 1, name: 'A', country: 'X'));
      ctx.authors.add(Author(id: 2, name: 'B', country: 'Y'));
      ctx.authors.remove(Author(id: 99, name: 'Z', country: 'W'));

      // Use a real SQL provider to get the right insert/update/
      // delete order. We snapshot the SQL log to assert on it.
      final int affected = ctx.saveChanges();
      expect(affected, 3);
      expect(provider.executed.length, 3);

      // INSERTs first. The MVP uses parameterised placeholders
      // (`?`) for every bind; the bind values are appended in
      // a comment for the test's benefit.
      expect(provider.executed[0], startsWith('INSERT INTO authors'));
      expect(provider.executed[0], contains("VALUES (?, ?)"));
      expect(provider.executed[0], contains("'A'"));
      expect(provider.executed[0], contains("'X'"));
      expect(provider.executed[1], startsWith('INSERT INTO authors'));
      expect(provider.executed[1], contains('B'));
      expect(provider.executed[1], contains('Y'));
      // DELETE last.
      expect(provider.executed[2], startsWith('DELETE FROM authors'));
      expect(provider.executed[2], contains('WHERE id = ?'));
      expect(provider.executed[2], contains('99'));
    });

    test('SaveChanges returns 0 for an empty tracker', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      expect(ctx.saveChanges(), 0);
      expect(provider.executed, isEmpty);
    });

    test(
        'markModified stages the entity for UPDATE on the next '
        'saveChanges', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      ctx.authors.markModified(a);
      expect(ctx.changeTracker.entries.single.state, EntityState.modified);
      expect(ctx.saveChanges(), 1);
      expect(provider.executed.single, startsWith('UPDATE authors'));
    });

    test('markUnchanged stages the entity as Unchanged (no SQL emitted)', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      ctx.authors.markUnchanged(a);
      expect(ctx.changeTracker.entries.single.state, EntityState.unchanged);
      expect(ctx.saveChanges(), 0);
      expect(provider.executed, isEmpty);
    });

    test('markDeleted is an alias for remove()', () {
      final _InMemoryProvider provider = _InMemoryProvider();
      final _TestContext ctx = _TestContext(provider);
      final Author a = Author(id: 1, name: 'X', country: 'Y');
      ctx.authors.markDeleted(a);
      expect(ctx.changeTracker.entries.single.state, EntityState.removed);
      expect(ctx.saveChanges(), 1);
      expect(provider.executed.single, startsWith('DELETE FROM authors'));
    });
  });
}

// ─── Test fixtures ──────────────────────────────────────────────────

class Author implements RecordLike {
  const Author({required this.id, required this.name, required this.country});
  final int id;
  final String name;
  final String country;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'name' => name,
        'country' => country,
        _ => null,
      };

  @override
  String toString() => 'Author(id: $id, name: $name, country: $country)';
}

class _Unknown {
  const _Unknown();
}

EntityMeta _authorMeta() {
  final ColumnMeta id = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta name = ColumnMeta(
    sqlName: 'name',
    dartField: 'name',
    dartType: String,
  );
  final ColumnMeta country = ColumnMeta(
    sqlName: 'country',
    dartField: 'country',
    dartType: String,
  );
  return EntityMeta(
    tableName: 'authors',
    columns: <ColumnMeta>[id, name, country],
    insertableColumns: <ColumnMeta>[name, country],
    updatableColumns: <ColumnMeta>[name, country],
    primaryKey: id,
    primaryKeyIndex: 0,
    pkOf: (Object e) => (e as Author).id,
  );
}

EntityMeta _nullableMeta() {
  final ColumnMeta id = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta description = ColumnMeta(
    sqlName: 'description',
    dartField: 'description',
    dartType: String,
    nullable: true,
  );
  final ColumnMeta rating = ColumnMeta(
    sqlName: 'rating',
    dartField: 'rating',
    dartType: int,
    defaultLiteral: '0',
  );
  return EntityMeta(
    tableName: 'notes',
    columns: <ColumnMeta>[id, description, rating],
    insertableColumns: <ColumnMeta>[description, rating],
    updatableColumns: <ColumnMeta>[description, rating],
    primaryKey: id,
    primaryKeyIndex: 0,
    pkOf: (Object e) => 1,
  );
}

EntityMeta _bookMeta() {
  // A `books` table with a foreign key to `authors(id)` and
  // a unique index on `isbn`. The codegen for a
  // `@Table class Book { @ForeignKey(table: 'authors',
  // column: 'id') final int authorId; @Index(unique: true,
  // name: 'books_isbn_unq') final String isbn; }` produces
  // exactly this EntityMeta.
  final ColumnMeta id = ColumnMeta(
    sqlName: 'id',
    dartField: 'id',
    dartType: int,
    isPrimaryKey: true,
    isAutoIncrement: true,
  );
  final ColumnMeta authorId = ColumnMeta(
    sqlName: 'author_id',
    dartField: 'authorId',
    dartType: int,
    isForeignKey: true,
    foreignTable: 'authors',
    foreignColumn: 'id',
  );
  final ColumnMeta title = ColumnMeta(
    sqlName: 'title',
    dartField: 'title',
    dartType: String,
  );
  final ColumnMeta isbn = ColumnMeta(
    sqlName: 'isbn',
    dartField: 'isbn',
    dartType: String,
    isIndexed: true,
    isUniqueIndex: true,
    indexName: 'books_isbn_unq',
  );
  return EntityMeta(
    tableName: 'books',
    columns: <ColumnMeta>[id, authorId, title, isbn],
    insertableColumns: <ColumnMeta>[authorId, title, isbn],
    updatableColumns: <ColumnMeta>[authorId, title, isbn],
    primaryKey: id,
    primaryKeyIndex: 0,
    pkOf: (Object e) => 1,
  );
}

/// A hand-rolled in-memory provider that records the SQL it is
/// asked to execute. The MVP `DbSet<T>` only calls `execute`
/// (not `select`), so the test records the bind parameters as
/// a textual snapshot alongside the SQL.
class _InMemoryProvider {
  final List<String> executed = <String>[];

  int callExecute(String sql, List<Object?> binds) {
    final StringBuffer buf = StringBuffer()..write(sql);
    if (binds.isNotEmpty) {
      buf.write('  -- binds: ${binds.map(_renderBind).join(', ')}');
    }
    executed.add(buf.toString());
    return 1;
  }

  static String _renderBind(Object? b) {
    if (b == null) return 'NULL';
    if (b is String) return "'$b'";
    return b.toString();
  }
}

class _TestContext extends DbContext {
  _TestContext(this._provider) {
    authors = dbSet<Author>(() => _authorMeta());
  }
  final _InMemoryProvider _provider;
  late final DbSet<Author> authors;

  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() metaAccessor) {
    return DbSet<T>(
      metaAccessor: metaAccessor,
      tracker: changeTracker,
      execute: _provider.callExecute,
      select: (String sql, List<Object?> binds) => <Object?>[],
      lastInsertRowId: () => 0,
    );
  }
}
