import 'dart:async';
import 'dart:math';

import 'package:d_rocket/d_rocket.dart';

// include_relation types are pulled in via the
// d_rocket barrel — no explicit import needed.

/// A typed, queryable collection of [T] entities backed by a
/// single SQL table.
///
/// Created by [DbContext.dbSet] (one `DbSet<T>` per
/// `@Table` class). All mutating operations (`add`,
/// `addRange`, `remove`) stage changes in the [DbContext]'s
/// [ChangeTracker]; the user must call
/// `DbContext.saveChanges` to flush the SQL.
///
/// `toList` and `findById` execute read-only SQL
/// immediately and are NOT staged in the change tracker.
class DbSet<T> {
  /// The `EntityMeta` for `T`. Set by the codegen on the
  /// `@Table` class as `static EntityMeta entityMeta`.
  final EntityMeta Function() _metaAccessor;

  /// The shared [ChangeTracker] (owned by the surrounding
  /// [DbContext]).
  final ChangeTracker _tracker;

  /// A function that executes a SQL statement with binds and
  /// returns the number of affected rows. The provider-agnostic
  /// abstraction lets the user plug in any backing store
  /// (SQLite, Postgres, in-memory, …).
  final int Function(String sql, List<Object?> binds) _execute;

  /// A function that executes a `SELECT` and returns the raw
  /// rows. The runtime does not interpret the row format; the
  /// `EntityMeta.fromRow` (provided by codegen) does.
  final List<Object?> Function(String sql, List<Object?> binds) _select;

  /// A function that fetches the last inserted row id (only
  /// meaningful for SQLite, where `lastInsertRowId` is a
  /// per-connection property). Defaults to a stub that throws
  /// if the user calls `SaveChanges` on an auto-increment PK
  /// without configuring the provider.
  final int Function() _lastInsertRowId;

  /// Optional [SqliteQueryProvider] accessor. Set by the
  /// surrounding [DbContext] via
  /// [attachSqliteProvider] when the user has constructed the
  /// context with a SQLite database. `null` when the
  /// underlying storage is not SQLite (or when the user
  /// does not opt into `asQueryable`).
  ///
  ///: moved to
  /// `d_rocket_provider_sqlite/lib/src/extension/db_set_extension.dart`.
  /// The core `DbSet<T>` no longer carries a
  /// `_sqliteProvider` field — the provider package
  /// does the attachment via `attach<SqliteQueryProvider>(p)`.

  ///: optional [AsyncQueryProvider] for
  /// the `*Async_` read methods (`toListAsync_`,
  /// `findByIdAsync`, `firstByAsync`, `allByAsync`,
  /// `toListWithJoinsAsync_`). Set by the surrounding
  /// [DbContext] via [attachAsyncProvider] when
  /// the user has constructed the context with a
  /// provider that implements [AsyncQueryProvider]
  /// (every built-in provider does).
  ///
  /// `null` when the user is using only the legacy
  /// sync API. The `*Async_` methods throw
  /// [StateError] when called without this set.
  AsyncQueryProvider? _asyncProvider;

  /// .e: a queue of pending navigation
  /// includes, populated by `.include_TNav(name,
  /// targetMeta)` calls. Cleared after
  /// `toListWithIncludesAsync_` applies them.
  ///
  /// Why we don't apply them in `toListAsync_`:
  /// some users want the raw list without
  /// includes (e.g. for counting). Splitting the
  /// API keeps the "include" an explicit opt-in.
  final List<DbSetInclude> _pendingIncludes = <DbSetInclude>[];

  /// (provider-agnostic): public
  /// accessor for the async provider, exposed so
  /// provider packages (`d_rocket_provider_*`)
  /// can read the wired backend without forcing
  /// the user to pass it in twice. The setter
  /// remains internal (use `attachAsyncProvider`).
  AsyncQueryProvider? get asyncProvider => _asyncProvider;

  /// (provider-agnostic): public
  /// accessor for the change tracker. Provider
  /// packages may need to feed entities into the
  /// tracker when materialising queryable rows.
  ChangeTracker get changeTracker => _tracker;

  // ───: provider attachments ───────────────────────
  //
  // The core ORM is provider-agnostic. Provider-specific
  // bridges (e.g. `asQueryable` for SQLite) live
  // in extension methods in the matching
  // `d_rocket_provider_*` package. The bridge stores its
  // provider in this map keyed by its [Type]. The user
  // calls `dbSet.attachSqlite(p)` and the SQLite package's
  // extension unpacks it on demand.

  final Map<Type, Object> _attachments = <Type, Object>{};

  /// Generic attachment hook used by provider-specific
  /// extensions (e.g. `d_rocket_provider_sqlite`'s
  /// `attachSqlite`). Idempotent. Returns `this` for
  /// chaining.
  DbSet<T> attach<P>(P provider) {
    _attachments[P] = provider as Object;
    return this;
  }

  /// Looks up an attached provider by type. Returns
  /// `null` when no provider of that type is attached.
  /// Provider-specific extensions use this to retrieve
  /// what they put in via [attach].
  P? get<P>() => _attachments[P] as P?;

  /// Attaches an [AsyncQueryProvider]
  /// for the `*Async` read methods. Idempotent. Returns
  /// `this` for chaining.
  DbSet<T> attachAsyncProvider(AsyncQueryProvider provider) {
    _asyncProvider = provider;
    return this;
  }

  DbSet({
    required EntityMeta Function() metaAccessor,
    required ChangeTracker tracker,
    required int Function(String sql, List<Object?> binds) execute,
    required List<Object?> Function(String sql, List<Object?> binds) select,
    required int Function() lastInsertRowId,
  })  : _metaAccessor = metaAccessor,
        _tracker = tracker,
        _execute = execute,
        _select = select,
        _lastInsertRowId = lastInsertRowId;

  /// The metadata for this `DbSet`. Read-only.
  EntityMeta get meta => _metaAccessor();

  /// Stages [entity] for insertion. The actual `INSERT` SQL
  /// runs on the next `DbContext.saveChanges`.
  void add(T entity) {
    _tracker.track(entity as Object, EntityState.added);
  }

  /// Stages [entities] for insertion in order.
  void addRange(Iterable<T> entities) {
    for (final T entity in entities) {
      add(entity);
    }
  }

  /// Stages [entity] for deletion. The actual `DELETE` SQL
  /// runs on the next `DbContext.saveChanges`.
  void remove(T entity) {
    _tracker.track(entity as Object, EntityState.removed);
  }

  /// Loads every row from the table. Returns the entities in
  /// the order the database yields them (no ordering is
  /// implied; use a LINQ `orderBy_` for that).
  ///
  /// Requires the codegen-supplied `EntityMeta.fromRow`
  /// . Throws [UnsupportedError] otherwise.
  List<T> toList() {
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.toList() requires the codegen-supplied '
        'EntityMeta.fromRow helper. Either run the '
        '`d_rocket_builder:table` codegen (Fase 3.5+) '
        'or construct entities directly and use `add` + '
        '`saveChanges` for now.',
      );
    }
    //: the SELECT includes the embedded
    // columns too (so the fromRow can read them).
    final List<ColumnMeta> cols = meta.allColumns;
    final String sql =
        'SELECT ${cols.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName}';
    final List<Object?> rawRows = _select(sql, const <Object?>[]);
    return _materialize(rawRows);
  }

  /// Loads the entity whose PK equals [id], or returns `null`
  /// if not found.
  ///
  /// Requires the codegen-supplied `EntityMeta.fromRow`
  /// . Throws [UnsupportedError] otherwise.
  ///
  ///: optional [include] callbacks let the
  /// caller eager-load navigation properties. Each
  /// callback is invoked after the entity is
  /// materialised; the typical pattern is:
  ///
  /// ```dart
  /// final Book? book = ctx.books.findById(1, include: [
  /// (Book b) => b.author = ctx.authors.firstBy(
  /// column: 'id', value: b.authorId),
  /// (Book b) => b.sales = ctx.sales.allBy(
  /// column: 'book_id', value: b.id),
  ///]);
  /// ```
  ///
  ///: optional [joins] (list of
  /// [IncludeRelation]s) emits a single SQL statement
  /// with `LEFT JOIN`s and materialises the result into
  /// `T` with the navigation properties populated. This
  /// is declarative and more efficient than the
  /// callback-based `include` (N+1 → 1 query). Example:
  ///
  /// ```dart
  /// final Book? book = ctx.books.findById(1, joins: [
  /// IncludeOne`<Book, Author>`(
  /// navigationName: 'author',
  /// relatedTable: 'authors',
  /// fkColumnOnT: 'author_id',
  ///),
  /// IncludeMany`<Book, Sale>`(
  /// navigationName: 'sales',
  /// relatedTable: 'sales',
  /// inverseFkColumn: 'book_id',
  ///),
  ///]);
  /// ```
  ///
  /// If both [joins] and [include] are supplied, the
  /// joins run first (single SQL), then the `include`
  /// callbacks run on the resulting entity (allowing
  /// post-processing of the eagerly-loaded relations).
  T? findById(
    Object id, {
    List<void Function(T)>? include,
    List<IncludeRelation<T, Object>>? joins,
  }) {
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.findById() requires the codegen-supplied '
        'EntityMeta.fromRow helper. Either run the '
        '`d_rocket_builder:table` codegen (Fase 3.5+) '
        'or construct entities directly and use `add` + '
        '`saveChanges for now.',
      );
    }
    if (joins == null || joins.isEmpty) {
      // No joins → single-table SELECT ( path).
      //: the SELECT includes the embedded
      // columns too (so the fromRow can read them).
      final String sql =
          'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
          'FROM ${meta.tableName} '
          'WHERE ${meta.primaryKey.sqlName} = ? '
          'LIMIT 1';
      final List<Object?> rawRows = _select(sql, <Object?>[id]);
      if (rawRows.isEmpty) return null;
      final List<T> entities = _materialize(rawRows);
      final T entity = entities.first;
      if (include != null) {
        for (final void Function(T) cb in include) {
          cb(entity);
        }
      }
      return entity;
    }

    // — JOIN-based eager loading (single SQL).
    //
    // Build a single SELECT with LEFT JOIN per relation.
    // The result is one row per combination (book ×
    // sales), so we group by the primary key and assign
    // each row's related columns to the navigation
    // property.
    final String mainAlias = 't0';
    final StringBuffer select = StringBuffer();
    final StringBuffer from = StringBuffer();
    final StringBuffer where = StringBuffer();

    // Main table columns.
    select.write(
      meta.columns
          .map((ColumnMeta c) => '$mainAlias."${c.sqlName}" AS "${c.sqlName}"')
          .join(', '),
    );
    from.write('"${meta.tableName}" AS $mainAlias');
    where.write('$mainAlias."${meta.primaryKey.sqlName}" = ?');

    // Add JOINs.
    for (int i = 0; i < joins.length; i++) {
      final IncludeRelation<T, Object> rel = joins[i];
      final String alias = 't${i + 1}';
      select.write(
        ', ${rel.relatedMeta.columns.map((ColumnMeta c) => '$alias."${c.sqlName}" AS '
            '"${rel.relatedMeta.tableName}_${c.sqlName}"').join(', ')}',
      );
      switch (rel) {
        case IncludeOne<T, Object>():
          from.write(
            ' LEFT JOIN "${rel.relatedMeta.tableName}" AS $alias ON '
            '$alias."id" = $mainAlias."${rel.fkColumnOnT}"',
          );
        case IncludeMany<T, Object>():
          from.write(
            ' LEFT JOIN "${rel.relatedMeta.tableName}" AS $alias ON '
            '$alias."${rel.inverseFkColumn}" = $mainAlias."id"',
          );
      }
    }

    final String sql = 'SELECT $select FROM $from WHERE $where';
    final List<Object?> rawRows = _select(sql, <Object?>[id]);
    if (rawRows.isEmpty) return null;

    // Materialise the main entity from the first row
    // (all rows share the same main-entity columns).
    final Map<String, Object?> mainRow = _projectMainRow(
      rawRows.first as Map<String, Object?>,
      joins,
    );
    final T entity = meta.fromRow!(mainRow) as T;

    // Populate navigation properties from the JOIN rows.
    for (int i = 0; i < joins.length; i++) {
      final IncludeRelation<T, Object> rel = joins[i];
      _populateNavigation(entity, rel, rawRows);
    }

    if (include != null) {
      for (final void Function(T) cb in include) {
        cb(entity);
      }
    }
    return entity;
  }

  /// helper: extract the main-entity columns
  /// from a JOIN row (stripping the `tableName_` prefix
  /// from the related columns).
  Map<String, Object?> _projectMainRow(
    Map<String, Object?> row,
    List<IncludeRelation<T, Object>> joins,
  ) {
    final Map<String, Object?> mainRow = <String, Object?>{};
    for (final MapEntry<String, Object?> e in row.entries) {
      final bool isRelated = joins.any((IncludeRelation<T, Object> rel) =>
          e.key.startsWith('${rel.relatedMeta.tableName}_'));
      if (!isRelated) {
        mainRow[e.key] = e.value;
      }
    }
    return mainRow;
  }

  /// helper: populate a navigation property
  /// from the JOIN rows. The strategy depends on the
  /// cardinality:
  /// * `IncludeOne` picks the first non-null row.
  /// * `IncludeMany` collects every non-null row.
  void _populateNavigation(
    T entity,
    IncludeRelation<T, Object> rel,
    List<Object?> rawRows,
  ) {
    final String prefix = '${rel.relatedMeta.tableName}_';
    // Collect every non-null related row (deduped).
    final List<Map<String, Object?>> relatedRows = <Map<String, Object?>>[];
    final Set<Object> seen = <Object>{};
    for (int i = 0; i < rawRows.length; i++) {
      final Map<String, Object?> row = rawRows[i] as Map<String, Object?>;
      // Use the related PK as the dedup key.
      final String pkKey = '${prefix}id';
      final Object? relatedPk = row[pkKey];
      if (relatedPk == null) continue;
      if (seen.contains(relatedPk)) continue;
      seen.add(relatedPk);
      final Map<String, Object?> related = <String, Object?>{};
      for (final MapEntry<String, Object?> e in row.entries) {
        if (e.key.startsWith(prefix)) {
          related[e.key.substring(prefix.length)] = e.value;
        }
      }
      relatedRows.add(related);
    }

    switch (rel) {
      case IncludeOne<T, Object>():
        if (relatedRows.isNotEmpty && rel.relatedMeta.fromRow != null) {
          (entity as dynamic).joinResults[rel.navigationName] =
              rel.relatedMeta.fromRow!(relatedRows.first);
        }
      case IncludeMany<T, Object>():
        if (rel.relatedMeta.fromRow != null) {
          (entity as dynamic).joinResults[rel.navigationName] = relatedRows
              .map((Map<String, Object?> r) => rel.relatedMeta.fromRow!(r))
              .toList();
        }
    }
  }

  /// .B (relations): returns the first entity
  /// in this `DbSet<T>` whose [column] equals [value],
  /// or `null` if no match.
  ///
  /// The primary use case is typed navigation between
  /// `@BelongsTo` / `@HasMany` relations:
  ///
  /// ```dart
  /// // @BelongsTo: load the author of a book
  /// final Author? author = ctx.authors.firstBy(
  /// column: 'id', value: book.authorId);
  /// // @HasMany: load the first sale of a book
  /// final Sale? first = ctx.sales.firstBy(
  /// column: 'book_id', value: book.id);
  /// ```
  ///
  /// Returns the typed `T` (or `null`); the column
  /// name is the SQL name (e.g. `'author_id'`, not
  /// `'authorId'`).
  ///
  /// Throws [StateError] if [column] is not declared in
  /// the `EntityMeta` (the column-name validation guards
  /// against SQL-injection through the column param).
  T? firstBy({required String column, required Object? value}) {
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.firstBy() requires the codegen-supplied '
        'EntityMeta.fromRow helper. Run the '
        '`d_rocket_builder:table` codegen.',
      );
    }
    if (!meta.columns.any((ColumnMeta c) => c.sqlName == column)) {
      throw StateError(
        'DbSet<T>.firstBy(): column "$column" is not declared in '
        'the EntityMeta of ${meta.tableName}. Declared columns: '
        '${meta.columns.map((ColumnMeta c) => c.sqlName).toList()}',
      );
    }
    final String sql =
        'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName} '
        'WHERE $column = ? '
        'LIMIT 1';
    final List<Object?> rawRows = _select(sql, <Object?>[value]);
    if (rawRows.isEmpty) return null;
    final List<T> entities = _materialize(rawRows);
    return entities.first;
  }

  /// .B (relations): returns every entity in
  /// this `DbSet<T>` whose [column] equals [value].
  ///
  /// The primary use case is typed navigation for
  /// `@HasMany`:
  ///
  /// ```dart
  /// // @HasMany: load every sale of a book
  /// final List`<Sale>` sales = ctx.sales.allBy(
  /// column: 'book_id', value: book.id);
  /// ```
  ///
  /// Throws [StateError] if [column] is not declared in
  /// the `EntityMeta`.
  List<T> allBy({required String column, required Object? value}) {
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.allBy() requires the codegen-supplied '
        'EntityMeta.fromRow helper. Run the '
        '`d_rocket_builder:table` codegen.',
      );
    }
    if (!meta.columns.any((ColumnMeta c) => c.sqlName == column)) {
      throw StateError(
        'DbSet<T>.allBy(): column "$column" is not declared in '
        'the EntityMeta of ${meta.tableName}. Declared columns: '
        '${meta.columns.map((ColumnMeta c) => c.sqlName).toList()}',
      );
    }
    final String sql =
        'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName} '
        'WHERE $column = ?';
    final List<Object?> rawRows = _select(sql, <Object?>[value]);
    return _materialize(rawRows);
  }

  /// Stages [entity] as Modified. The actual `UPDATE` SQL
  /// runs on the next `DbContext.saveChanges`.
  ///
  /// Unlike `add` / `remove`, the user is responsible for
  /// first attaching the entity to the tracker (typically via
  /// a previous `add` + `saveChanges` or a `findById`).
  /// If the entity is not tracked, this method adds it in the
  /// `Modified` state with empty `originalValues` (the runtime
  /// does not maintain a per-column "before" snapshot in the
  /// MVP; concurrent-update detection via `originalValues` is
  /// a feature).
  void markModified(T entity) {
    _tracker.track(entity as Object, EntityState.modified);
  }

  /// Stages [entity] as Unchanged. Useful after a manual
  /// flush that the runtime does not know about, or for
  /// pre-tracking an entity that was loaded out-of-band.
  void markUnchanged(T entity) {
    _tracker.track(entity as Object, EntityState.unchanged);
  }

  /// Stages [entity] for deletion. The actual `DELETE` SQL
  /// runs on the next `DbContext.saveChanges`.
  /// (Alias for [remove] for consistency with the EF Core
  /// nomenclature.)
  void markDeleted(T entity) => remove(entity);

  /// Drops all locally-tracked entries for `T`. Useful for
  /// tests and for "forget what I did" patterns.
  void clearLocalChanges() {
    _tracker.entries
        .where((TrackedEntry e) => e.entity is T)
        .toList()
        .forEach((TrackedEntry e) {
      _tracker.untrack(meta.pkOf(e.entity));
    });
  }

  // ─── Internals used by DbContext.saveChanges ──────────

  /// Builds the `INSERT INTO ... VALUES (?, ?, ...)` SQL for
  /// [entity] and executes it. Returns the number of rows
  /// affected (always 1 for a successful insert).
  int insertOne(T entity) {
    // Auto-fill auto-incrementing PKs the user
    // did not set:
    //   - `int` PK + isAutoIncrement: leave the
    //     field null. SQLite's
    //     `INTEGER PRIMARY KEY AUTOINCREMENT`
    //     assigns the value after the INSERT and
    //     the runtime back-propagates it via
    //     `lastInsertedPk()`.
    //   - `String` PK + isAutoIncrement: generate
    //     a UUID v4 here and set it on the entity
    //     via `meta.setId` (the codegen-supplied
    //     closure). The column DDL is
    //     `id TEXT PRIMARY KEY` (no AUTOINCREMENT).
    //   - Any other type + isAutoIncrement:
    //     leave the field null. The user is
    //     expected to set a value before calling
    //     `saveChanges`, otherwise the INSERT
    //     will fail with a NOT NULL constraint
    //     violation.
    // ignore: unnecessary_nullable_for_final_variable_declarations
    final ColumnMeta? pk = meta.primaryKey;
    if (pk != null && pk.isAutoIncrement) {
      final Object? currentValue = _readField(entity, pk);
      if (currentValue == null && pk.dartType == String) {
        final String uuid = generateUuidV4();
        final void Function(Object, Object)? setter = meta.setId;
        setter?.call(entity as Object, uuid);
      }
    }

    // (TPH): use `effectiveInsertableColumns`
    // (not `insertableColumns`) so the INSERT also
    // includes the TPH children's columns. A `Cat`
    // row gets `indoor` set, a `Dog` row gets `breed`.
    final List<ColumnMeta> cols = meta.effectiveInsertableColumns;
    final String placeholders =
        List<String>.filled(cols.length, '?').join(', ');
    final String sql = 'INSERT INTO ${meta.tableName} '
        '(${cols.map((ColumnMeta c) => c.sqlName).join(', ')}) '
        'VALUES ($placeholders)';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
    ];
    return _execute(sql, binds);
  }

  ///: returns the `lastInsertRowId` of the last
  /// INSERT run through this `DbSet`. Used by
  /// [DbContext] to back-propagate the PK right
  /// after each insert ( back-propagation was
  /// buggy: it read the `lastInsertRowId` AFTER the entire
  /// inserts loop, so all inserted entities ended up with
  /// the last PK).
  ///
  /// Returns `null` if the provider does not support
  /// `lastInsertRowId` (e.g., the in-memory test fixture).
  int? lastInsertedPk() {
    try {
      return _lastInsertRowId();
    } catch (_) {
      return null;
    }
  }

  ///: variant of [insertOne] that runs the SQL
  /// through a [MigrationExecutor] (a transaction-scoped
  /// callback). Used by [DbContext] when the
  /// surrounding batch is wrapped in a transaction
  /// (`createSaveChangesTransaction` is set).
  ///
  /// Returns the PK of the inserted row (read from
  /// `_lastInsertRowId` right after the executor
  /// ran). Returns `null` when the provider does not
  /// support `lastInsertRowId`.
  ///
  /// Does NOT back-propagate the PK (caller's job; the
  /// transaction should be committed before any
  /// back-propagation is observed by the user).
  int? insertOneWith(T entity, MigrationExecutor exec) {
    // (TPH): see `insertOne`.
    final List<ColumnMeta> cols = meta.effectiveInsertableColumns;
    final String placeholders =
        List<String>.filled(cols.length, '?').join(', ');
    final String sql = 'INSERT INTO ${meta.tableName} '
        '(${cols.map((ColumnMeta c) => c.sqlName).join(', ')}) '
        'VALUES ($placeholders)';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
    ];
    exec(sql, binds);
    return lastInsertedPk();
  }

  /// Back-propagates the DB-assigned PK to the [entity]
  /// instance in-place. Called by
  /// [DbContext.saveChanges] right after a successful
  /// `INSERT` when the PK is auto-incremented. Requires the
  /// codegen-supplied `EntityMeta.setId` .
  ///
  /// Silently no-ops if:
  /// * the PK is not auto-increment (the entity's PK is the
  /// one the user supplied), or
  /// * the codegen did not emit a `setId` hook (e.g. the
  /// user hand-wrote the EntityMeta in a test fixture, or
  /// the PK field is `final`).
  ///
  /// The codegen does throw at build time if the PK field
  /// is `final` (so a missing `setId` at runtime usually
  /// means "hand-rolled meta" — and the user has chosen to
  /// accept that trade-off).
  void backPropagatePk(T entity) {
    if (!meta.primaryKey.isAutoIncrement) {
      return; // nothing to do; the entity's PK is the one the user supplied
    }
    final void Function(Object, Object)? setter = meta.setId;
    if (setter == null) {
      return; // No-op: the user did not configure a setter
      // (probably a hand-rolled test fixture or a
      // legacy entity that uses `final` PKs).
    }
    setter(entity as Object, _lastInsertRowId());
  }

  /// Returns the last-inserted row id, typically used by the
  /// surrounding [DbContext] to update the auto-PK of a
  /// freshly inserted entity.
  int lastInsertRowId() => _lastInsertRowId();

  /// Builds the `UPDATE ... SET ... WHERE pk = ?` SQL for
  /// [entity] and executes it. Returns the number of rows
  /// affected.
  int updateOne(T entity, Map<String, Object?> originalValues) {
    // (TPH): see `insertOne`.
    final List<ColumnMeta> cols = meta.effectiveUpdatableColumns;
    final String setClause =
        cols.map((ColumnMeta c) => '${c.sqlName} = ?').join(', ');
    final String sql = 'UPDATE ${meta.tableName} '
        'SET $setClause '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
      _readField(entity, meta.primaryKey),
    ];
    return _execute(sql, binds);
  }

  ///: variant of [updateOne] that runs the SQL
  /// through a [MigrationExecutor]. See [insertOneWith].
  int updateOneWith(
    T entity,
    Map<String, Object?> originalValues,
    MigrationExecutor exec,
  ) {
    // (TPH): see `insertOne`.
    final List<ColumnMeta> cols = meta.effectiveUpdatableColumns;
    final String setClause =
        cols.map((ColumnMeta c) => '${c.sqlName} = ?').join(', ');
    final String sql = 'UPDATE ${meta.tableName} '
        'SET $setClause '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
      _readField(entity, meta.primaryKey),
    ];
    exec(sql, binds);
    return 1;
  }

  /// Builds the `DELETE FROM ... WHERE pk = ?` SQL for [entity]
  /// and executes it. Returns the number of rows affected.
  int deleteOne(T entity) {
    final String sql = 'DELETE FROM ${meta.tableName} '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    return _execute(sql, <Object?>[_readField(entity, meta.primaryKey)]);
  }

  // ───: async I/O write methods ────────────────────────
  //
  // These are the async counterparts of [insertOne],
  // [updateOne], [deleteOne], [lastInsertedPk]. They use the
  // [AsyncQueryProvider] attached via [attachAsyncProvider].
  // The sync methods continue to work (.x behaviour is
  // preserved; no breaking change).
  //
  // Used by [DbContext.saveChangesAsync]
  // to flush the change tracker via the async path.

  /// (async): the async counterpart of
  /// [insertOne]. Runs the same `INSERT INTO …` SQL through
  /// the [AsyncQueryProvider].
  ///
  /// Throws [StateError] if no [AsyncQueryProvider] is
  /// attached.
  Future<int> insertOneAsync(T entity) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.insertOneAsync() requires an AsyncQueryProvider. '
        'Call attachAsyncProvider(...) on this DbSet, or '
        'configure the surrounding DbContext with one.',
      );
    }
    // (TPH): see `insertOne`.
    final List<ColumnMeta> cols = meta.effectiveInsertableColumns;
    final String placeholders =
        List<String>.filled(cols.length, '?').join(', ');
    final String sql = 'INSERT INTO ${meta.tableName} '
        '(${cols.map((ColumnMeta c) => c.sqlName).join(', ')}) '
        'VALUES ($placeholders)';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
    ];
    await _asyncProvider!.executeAsync(sql, binds);
    return 1;
  }

  /// (async): the async counterpart of
  /// [updateOne]. Runs the same `UPDATE … SET …` SQL through
  /// the [AsyncQueryProvider].
  Future<int> updateOneAsync(
    T entity,
    Map<String, Object?> originalValues,
  ) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.updateOneAsync() requires an AsyncQueryProvider.',
      );
    }
    // (TPH): see `insertOne`.
    final List<ColumnMeta> cols = meta.effectiveUpdatableColumns;
    final String setClause =
        cols.map((ColumnMeta c) => '${c.sqlName} = ?').join(', ');
    final String sql = 'UPDATE ${meta.tableName} '
        'SET $setClause '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    final List<Object?> binds = <Object?>[
      for (final ColumnMeta c in cols) _readField(entity, c),
      _readField(entity, meta.primaryKey),
    ];
    await _asyncProvider!.executeAsync(sql, binds);
    return 1;
  }

  /// (async): the async counterpart of
  /// [deleteOne]. Runs the same `DELETE FROM …` SQL through
  /// the [AsyncQueryProvider].
  Future<int> deleteOneAsync(T entity) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.deleteOneAsync() requires an AsyncQueryProvider.',
      );
    }
    final String sql = 'DELETE FROM ${meta.tableName} '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    await _asyncProvider!.executeAsync(
      sql,
      <Object?>[_readField(entity, meta.primaryKey)],
    );
    return 1;
  }

  /// (async): the async counterpart of
  /// [lastInsertedPk]. Returns the last-inserted row id
  /// via the [AsyncQueryProvider]. Returns `null` if the
  /// provider does not support `lastInsertRowId` (e.g., the
  /// Postgres provider until wires it up via
  /// `RETURNING`).
  Future<int?> lastInsertedPkAsync() async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.lastInsertedPkAsync() requires an AsyncQueryProvider.',
      );
    }
    try {
      return await _asyncProvider!.lastInsertRowIdAsync();
    } catch (_) {
      return null;
    }
  }

  ///: variant of [deleteOne] that runs the SQL
  /// through a [MigrationExecutor]. See [insertOneWith].
  int deleteOneWith(T entity, MigrationExecutor exec) {
    final String sql = 'DELETE FROM ${meta.tableName} '
        'WHERE ${meta.primaryKey.sqlName} = ?';
    exec(sql, <Object?>[_readField(entity, meta.primaryKey)]);
    return 1;
  }

  /// Reads the value of [col] from [entity]. Prefers the
  /// codegen-supplied `readColumn` hook; falls back to the
  /// `RecordLike` interface.
  Object? _readField(T entity, ColumnMeta col) {
    final Object e = entity as Object;
    final Object? Function(Object, ColumnMeta)? hook = meta.readColumn;
    if (hook != null) {
      return hook(e, col);
    }
    if (e is RecordLike) {
      return e.readField(col.dartField);
    }
    throw StateError(
      'Cannot read field "${col.dartField}" on $T. '
      'The entity must `extends Record` (or implement '
      'RecordLike directly) for the ORM to read its fields. '
      'If you cannot extend Record (e.g. it is already a '
      'subclass of something else), implement `RecordLike` '
      'manually.',
    );
  }

  /// (public, for sync pipeline):
  /// reads a single column from an entity. Used by
  /// the sync pipeline to serialise an entity to a
  /// `Map<String, Object?>` for transport. Public so
  /// the context (which is a friend) can call it
  /// without reflection.
  Object? readFieldForTest(T entity, ColumnMeta col) => _readField(entity, col);

  ///: returns the [EntityMeta] that owns the
  /// [fromRow] factory for the given [row]. When the
  /// [meta] is a TPH root, this is the right child's meta
  /// (looked up by the row's discriminator value). When
  /// the [meta] is a TPH child, this is [meta] itself
  /// (already the right meta). For non-TPH entities, this
  /// is [meta].
  EntityMeta _resolveForRow(Map<String, Object?> row) {
    final ColumnMeta? discCol = meta.discriminatorColumn;
    if (discCol == null) return meta;
    final Object? discValue = row[discCol.sqlName];
    return meta.resolveForDiscriminator(discValue);
  }

  /// Materialises a list of raw row maps (one map per row,
  /// keyed by the SQL column names) into a list of `T`
  /// instances.
  ///
  ///: this is where the codegen-supplied
  /// `EntityMeta.fromRow` is invoked. Each row is fed to
  /// `fromRow`, which knows how to construct a `T` from the
  /// column values.
  ///
  ///: when the meta is a TPH root, the
  /// row's discriminator column is read to pick the
  /// right subclass's `fromRow` factory. This way, the
  /// `DbSet<Animal>.toList` materialises `Dog` and
  /// `Cat` instances automatically (returned as
  /// `List<Animal>`).
  List<T> _materialize(List<Object?> rawRows) {
    final List<T> out = <T>[];
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.toList() / findById() require a codegen-'
        'supplied `EntityMeta.fromRow`. Run the '
        '`d_rocket_builder:table` codegen to '
        'regenerate this entity.',
      );
    }
    for (final Object? raw in rawRows) {
      // The `select` callback is documented to return a
      // `List<Map<String, Object?>>` when the underlying
      // provider is SQLite. Other providers might return a
      // list of typed Row objects that happen to also be
      // `Map<String, Object?>`-compatible.
      if (raw is Map<String, Object?>) {
        //: resolve the right subclass
        // meta based on the row's discriminator value.
        final EntityMeta effective = _resolveForRow(raw);
        final Object Function(Map<String, Object?>)? childFromRow =
            effective.fromRow;
        if (childFromRow == null) {
          throw UnsupportedError(
            'DbSet<T>._materialize(): child meta '
            '${effective.tableName} has no fromRow '
            'factory. Run the codegen to regenerate.',
          );
        }
        out.add(childFromRow(raw) as T);
      } else {
        throw FormatException(
          'DbSet<T>.toList() expected each row to be a '
          'Map<String, Object?>, but got ${raw.runtimeType}. '
          'Check that the provider\'s `select` callback '
          'returns rows in that shape.',
        );
      }
    }
    return out;
  }

  //: the SQLite-specific
  // `asQueryable` extension moved to the
  // `d_rocket_provider_sqlite` package. The
  // provider-agnostic `DbSet<T>` exposes the public
  // `meta` / `changeTracker` / `asyncProvider`
  // accessors that the provider extension uses to
  // build a `Queryable<T>` without depending on
  // `package:sqlite3` here.

  // ───: async I/O read methods ─────────────────────
  //
  // These are the async counterparts of [toList],
  // [findById], [firstBy], [allBy]. They use the
  // [AsyncQueryProvider] attached via [attachAsyncProvider]
  // (or the [DbContext] constructor). If no async
  // provider is set, they throw [StateError] (the sync
  // methods still work as before).
  //
  // The I/O is real async (for Postgres / MySQL providers
  // coming in). For the built-in SQLite provider
  // the underlying binding is still synchronous — but the
  // API surface is async so that the same code works against
  // any future provider.

  /// (async): the async counterpart of
  /// [toList]. Returns the same `List<T>` once the
  /// underlying SQL has executed.
  ///
  /// Throws [StateError] if no [AsyncQueryProvider] is
  /// attached (use [attachAsyncProvider] or set one
  /// on the surrounding [DbContext]).
  Future<List<T>> toListAsync_() async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.toListAsync_() requires an AsyncQueryProvider. '
        'Call attachAsyncProvider(...) on this DbSet, or '
        'configure the surrounding DbContext with one.',
      );
    }
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.toListAsync_() requires the codegen-supplied '
        'EntityMeta.fromRow helper (Fase 3.5+).',
      );
    }
    //: the SELECT includes the embedded
    // columns too (so the fromRow can read them).
    final List<ColumnMeta> cols = meta.allColumns;
    final String sql =
        'SELECT ${cols.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName}';
    final List<Object?> rawRows =
        await _asyncProvider!.selectAsync(sql, const <Object?>[]);
    return _materialize(rawRows);
  }

  /// .e: chainable include of a navigation
  /// property. Records the include in the queue and
  /// returns this DbSet (so it can chain with
  /// `.where_`, `.orderBy_`, etc.).
  ///
  /// The actual populate happens on
  /// [toListWithIncludesAsync_] (a separate call from
  /// [toListAsync_]) so users who want the raw list
  /// without populating can still get it.
  ///
  /// Usage (.e, codegen-emitted typed form):
  /// ```dart
  /// final orders = await db
  /// .set`<Order>`
  /// .include_`<Customer>`
  /// .where_((o) => o.customer.name == 'John')
  /// .toListWithIncludesAsync_;
  /// ```
  ///
  /// The builder emits a typed wrapper per navigation,
  /// so `.include_<Customer>` is shorthand for the
  /// string-based `include_<TNav>(name, targetMeta)`.
  /// The generic [TNav] is for documentation; the
  /// runtime doesn't use it.
  DbSet<T> include_<TNav>(String name, EntityMeta targetMeta) {
    _pendingIncludes.add(DbSetInclude(
      name: name,
      targetMeta: targetMeta,
    ));
    return this;
  }

  /// .e: like [toListAsync_] but also
  /// applies any pending [include_] calls. Returns
  /// the same list, with the [NavigationRegistry]
  /// populated for the included navigations.
  ///
  /// Chainable form:
  /// ```dart
  /// final orders = await db
  /// .set`<Order>`
  /// .include_`<Customer>`
  /// .toListWithIncludesAsync_;
  /// // now orders[i].customer is populated
  /// ```
  Future<List<T>> toListWithIncludesAsync_() async {
    // 1. Fetch the main entities (existing path).
    final List<T> entities = await toListAsync_();
    // 2. Apply each pending include.
    for (final DbSetInclude inc in _pendingIncludes) {
      await NavigationPopulator.populate<dynamic>(
        entities: entities.cast<Object>(),
        sourceMeta: meta,
        targetMeta: inc.targetMeta,
        navigationName: inc.name,
        selectFn: (String sql, List<Object?> binds) async {
          if (_asyncProvider == null) {
            throw StateError(
              'toListWithIncludesAsync_() requires an AsyncQueryProvider '
              'to execute the batched navigation fetch.',
            );
          }
          return _asyncProvider!.selectAsync(sql, binds);
        },
      );
    }
    // 3. Clear the queue for reuse (or chaining).
    _pendingIncludes.clear();
    return entities;
  }

  /// (async): the async counterpart of
  /// [findById]. Returns the entity whose PK equals [id],
  /// or `null` if not found.
  ///
  /// The [joins] and [include] parameters behave the same
  /// as in [findById].
  Future<T?> findByIdAsync(
    Object id, {
    List<void Function(T)>? include,
    List<IncludeRelation<T, Object>>? joins,
  }) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.findByIdAsync() requires an AsyncQueryProvider.',
      );
    }
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.findByIdAsync() requires the codegen-supplied '
        'EntityMeta.fromRow helper (Fase 3.5+).',
      );
    }
    if (joins == null || joins.isEmpty) {
      // No joins → single-table SELECT (same SQL as the
      // sync findById).
      final String sql =
          'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
          'FROM ${meta.tableName} '
          'WHERE ${meta.primaryKey.sqlName} = ? '
          'LIMIT 1';
      final List<Object?> rawRows =
          await _asyncProvider!.selectAsync(sql, <Object?>[id]);
      if (rawRows.isEmpty) return null;
      final List<T> entities = _materialize(rawRows);
      final T entity = entities.first;
      if (include != null) {
        for (final void Function(T) cb in include) {
          cb(entity);
        }
      }
      return entity;
    }

    // — JOIN-based eager loading (single SQL).
    //
    // The SQL building logic is the same as the sync
    // findById, but the I/O is async.
    final String mainAlias = 't0';
    final StringBuffer select = StringBuffer();
    final StringBuffer from = StringBuffer();
    final StringBuffer where = StringBuffer();

    select.write(
      meta.columns
          .map((ColumnMeta c) => '$mainAlias."${c.sqlName}" AS "${c.sqlName}"')
          .join(', '),
    );
    from.write('"${meta.tableName}" AS $mainAlias');
    where.write('$mainAlias."${meta.primaryKey.sqlName}" = ?');

    for (int i = 0; i < joins.length; i++) {
      final IncludeRelation<T, Object> rel = joins[i];
      final String alias = 't${i + 1}';
      select.write(
        ', ${rel.relatedMeta.columns.map((ColumnMeta c) => '$alias."${c.sqlName}" AS '
            '"${rel.relatedMeta.tableName}_${c.sqlName}"').join(', ')}',
      );
      switch (rel) {
        case IncludeOne<T, Object>():
          from.write(
            ' LEFT JOIN "${rel.relatedMeta.tableName}" AS $alias ON '
            '$alias."id" = $mainAlias."${rel.fkColumnOnT}"',
          );
        case IncludeMany<T, Object>():
          from.write(
            ' LEFT JOIN "${rel.relatedMeta.tableName}" AS $alias ON '
            '$alias."${rel.inverseFkColumn}" = $mainAlias."id"',
          );
      }
    }

    final String sql = 'SELECT $select FROM $from WHERE $where';
    final List<Object?> rawRows =
        await _asyncProvider!.selectAsync(sql, <Object?>[id]);
    if (rawRows.isEmpty) return null;

    final Map<String, Object?> mainRow = _projectMainRow(
      rawRows.first as Map<String, Object?>,
      joins,
    );
    final T entity = meta.fromRow!(mainRow) as T;

    for (int i = 0; i < joins.length; i++) {
      final IncludeRelation<T, Object> rel = joins[i];
      _populateNavigation(entity, rel, rawRows);
    }

    if (include != null) {
      for (final void Function(T) cb in include) {
        cb(entity);
      }
    }
    return entity;
  }

  /// (async): the async counterpart of
  /// [firstBy]. Returns the first entity whose [column]
  /// equals [value], or `null` if no match.
  Future<T?> firstByAsync({
    required String column,
    required Object? value,
  }) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.firstByAsync() requires an AsyncQueryProvider.',
      );
    }
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.firstByAsync() requires the codegen-supplied '
        'EntityMeta.fromRow helper (Fase 3.5+).',
      );
    }
    if (!meta.columns.any((ColumnMeta c) => c.sqlName == column)) {
      throw StateError(
        'DbSet<T>.firstByAsync(): column "$column" is not declared in '
        'the EntityMeta of ${meta.tableName}. Declared columns: '
        '${meta.columns.map((ColumnMeta c) => c.sqlName).toList()}',
      );
    }
    final String sql =
        'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName} '
        'WHERE $column = ? '
        'LIMIT 1';
    final List<Object?> rawRows =
        await _asyncProvider!.selectAsync(sql, <Object?>[value]);
    if (rawRows.isEmpty) return null;
    final List<T> entities = _materialize(rawRows);
    return entities.first;
  }

  /// (async): the async counterpart of
  /// [allBy]. Returns every entity whose [column] equals
  /// [value].
  Future<List<T>> allByAsync({
    required String column,
    required Object? value,
  }) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.allByAsync() requires an AsyncQueryProvider.',
      );
    }
    if (meta.fromRow == null) {
      throw UnsupportedError(
        'DbSet<T>.allByAsync() requires the codegen-supplied '
        'EntityMeta.fromRow helper (Fase 3.5+).',
      );
    }
    if (!meta.columns.any((ColumnMeta c) => c.sqlName == column)) {
      throw StateError(
        'DbSet<T>.allByAsync(): column "$column" is not declared in '
        'the EntityMeta of ${meta.tableName}. Declared columns: '
        '${meta.columns.map((ColumnMeta c) => c.sqlName).toList()}',
      );
    }
    final String sql =
        'SELECT ${meta.allColumns.map((ColumnMeta c) => meta.sqlColumnName(c)).join(', ')} '
        'FROM ${meta.tableName} '
        'WHERE $column = ?';
    final List<Object?> rawRows =
        await _asyncProvider!.selectAsync(sql, <Object?>[value]);
    return _materialize(rawRows);
  }

  // ───: bulk operations on DbSet<T> ───
  //
  // Typed convenience methods that wrap the
  // [BulkOpsAsync] extension . The
  // user calls these on the DbSet (not on the
  // raw provider) so the table name comes from
  // the [EntityMeta] automatically — the user
  // never has to type it.

  ///: runs a single
  /// `UPDATE <T.tableName> SET col1 = ?, col2 = ? [WHERE ...]`
  /// statement.
  ///
  /// The table name comes from
  /// `entityMeta.tableName` — the user never has
  /// to type it. [setters] is the
  /// `column → value` map (column names are
  /// raw SQL — they're not entity field names,
  /// to match the underlying SQL).
  ///
  /// Returns the number of affected rows.
  ///
  /// Requires an [AsyncQueryProvider] to be
  /// attached ( contract).
  Future<int> executeBulkUpdate({
    required Map<String, Object?> setters,
    String? where,
    List<Object?>? whereBinds,
  }) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.executeBulkUpdate() requires an '
        'AsyncQueryProvider. Call attachAsyncProvider(...) '
        'on this DbSet, or configure the surrounding '
        'DbContext with one.',
      );
    }
    return _asyncProvider!.executeUpdateAsync(
      table: meta.tableName,
      setters: setters,
      where: where,
      whereBinds: whereBinds,
    );
  }

  ///: runs a single
  /// `DELETE FROM <T.tableName> [WHERE ...]`
  /// statement.
  ///
  /// Returns the number of affected rows.
  /// Requires an [AsyncQueryProvider] to be
  /// attached.
  Future<int> executeBulkDelete({
    String? where,
    List<Object?>? whereBinds,
  }) async {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.executeBulkDelete() requires an '
        'AsyncQueryProvider. Call attachAsyncProvider(...) '
        'on this DbSet, or configure the surrounding '
        'DbContext with one.',
      );
    }
    return _asyncProvider!.executeDeleteAsync(
      table: meta.tableName,
      where: where,
      whereBinds: whereBinds,
    );
  }

  // ───: reactive queries (DbSet.watch) ───
  //
  // The user subscribes to a `Stream<List<T>>` that
  // re-emits the current contents of the table on
  // every [pollInterval] tick. Designed for
  // Flutter's `StreamBuilder` widget — the
  // classic reactive query pattern.
  //
  // The MVP uses a periodic poll. A future
  // iteration can wire the stream
  // to the change tracker so it re-emits
  // immediately on `saveChangesAsync` (instead of
  // waiting for the next tick).

  ///: returns a `Stream<List<T>>` that
  /// emits the current rows of this DbSet, then
  /// re-emits on every [pollInterval] tick.
  ///
  /// Designed for Flutter's `StreamBuilder`:
  ///
  /// ```dart
  /// StreamBuilder<List`<Book>`>(
  /// stream: dbSet.books.watch,
  /// builder: (context, snapshot) {
  /// if (!snapshot.hasData) {
  /// return CircularProgressIndicator;
  /// }
  /// return ListView(
  /// children: snapshot.data!
  /// .map((b) => ListTile(title: Text(b.title)))
  /// .toList,
  ///);
  /// },
  ///)
  /// ```
  ///
  /// The default [pollInterval] is 1 second —
  /// long enough to be battery-friendly, short
  /// enough that the user perceives the UI as
  /// "live". Override for tighter / looser
  /// update rates.
  ///
  /// Requires an [AsyncQueryProvider] to be
  /// attached.
  Stream<List<T>> watch({
    Duration pollInterval = const Duration(seconds: 1),
  }) {
    if (_asyncProvider == null) {
      throw StateError(
        'DbSet<T>.watch() requires an AsyncQueryProvider. '
        'Call attachAsyncProvider(...) on this DbSet, or '
        'configure the surrounding DbContext with one.',
      );
    }
    //: periodic-poll stream. Emits
    // the current rows on every tick. Stops
    // cleanly when the subscriber cancels.
    // + 5.8.1: combined stream. The
    // generator listens to BOTH the periodic
    // poll AND the change-tracker `changes`
    // stream. On EITHER source firing, it
    // re-queries the table and yields. Stops
    // cleanly when the subscriber cancels.
    return _watchGenerator(pollInterval);
  }

  /// (internal): the async generator
  /// for [watch]. Emits the current rows on every
  /// [pollInterval] tick AND on every
  /// `ChangeTracker.changes` event.
  ///
  /// The two sources are combined: the generator
  /// yields after either fires. The first
  /// emission is the initial state (so subscribers
  /// don't have to wait for the first tick).
  Stream<List<T>> _watchGenerator(Duration pollInterval) async* {
    //: listen to the tracker's
    // changes. The listener triggers a re-emit
    // by completing `_changeCompleter`.
    Completer<void> changeCompleter = Completer<void>();
    final StreamSubscription<ChangeEvent> sub =
        _tracker.changes.listen((ChangeEvent _) {
      if (!changeCompleter.isCompleted) {
        changeCompleter.complete();
      }
    });
    try {
      while (true) {
        yield await toListAsync_();
        // Race: the next emission is triggered by
        // EITHER the periodic timer OR a tracker
        // change. Whichever fires first wins.
        final Future<void> timer = Future<void>.delayed(pollInterval);
        final Future<void> trigger = changeCompleter.future;
        await Future.any(<Future<void>>[timer, trigger]);
        // Reset the completer for the next tick.
        if (changeCompleter.isCompleted) {
          // ignore: discarded_futures
          changeCompleter = Completer<void>();
        }
      }
    } finally {
      await sub.cancel();
    }
  }
}

/// Generates a random UUID v4 string in the
/// canonical 8-4-4-4-12 lowercase hex form
/// (for example `f47ac10b-58cc-4372-a567-0e02b2c3d479`).
///
/// The version nibble (the 13th hex digit) is
/// `4` and the variant nibble (the 17th hex
/// digit) is in the `8`/`9`/`a`/`b` range, as
/// required by [RFC 4122](https://www.rfc-editor.org/rfc/rfc4122).
/// Backed by `Random.secure()` so the output
/// is suitable for use as a database primary
/// key without coordination.
///
/// Exposed at the top level (not nested in
/// `DbSet`) so the codegen and the unit tests
/// in `test/orm_runtime_test.dart` can call it
/// directly. Internal callers in this file
/// use the unprefixed name.
String generateUuidV4() {
  final Random random = Random.secure();
  final List<int> bytes =
      List<int>.generate(16, (_) => random.nextInt(256));
  // Set version to 4 (byte 6: top nibble = 0100).
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  // Set variant to RFC 4122 (byte 8: top 2 bits = 10).
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  final String hex = bytes
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-'
      '${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-'
      '${hex.substring(20, 32)}';
}
