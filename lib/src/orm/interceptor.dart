/// The DbInterceptor contract (Phase 3.7).
///
/// Inspired by EF Core's `SaveChangesInterceptor` +
/// NestJS's `Interceptor` + Prisma's (deprecated)
/// middleware. A `DbInterceptor` lets you transform,
/// log, or abort ORM operations **before** they
/// hit the wire and **after** the result comes
/// back.
///
/// ## Two-level granularity
///
/// The interceptor system has two granularities
/// that compose:
///
/// 1. **Command-level** (`onQuery`, `onMutation`,
///    `onQueryComplete`, `onMutationComplete`) —
///    fires once per SQL command. Use for query
///    rewriting (e.g. add `WHERE tenant_id = ?`),
///    logging, encryption at the SQL level.
///
/// 2. **Entity-level** (`onEntitySaving`,
///    `onEntitySaved`, `onSaveChangesStart`,
///    `onSaveChangesEnd`) — fires once per
///    `saveChanges()` call, with full visibility
///    into the per-entity changes. Use for
///    audit log, validation, soft-delete
///    decisions, business invariants.
///
/// ## Composition
///
/// Multiple interceptors are composed in
/// insertion order. Each `onX` method is called
/// in order; the result of interceptor N becomes
/// the input of interceptor N+1. Throwing in any
/// `onX` method aborts the chain (and the
/// operation).
///
/// Example:
///
/// ```dart
/// class TenantFilter extends DbInterceptor {
///   final int tenantId;
///   TenantFilter(this.tenantId);
///
///   @override
///   Future<QueryCommand> onQuery(QueryCommand cmd) async {
///     if (cmd.table == 'user' && !cmd.sql.contains('WHERE')) {
///       return cmd.copyWith(
///         sql: '${cmd.sql} WHERE tenant_id = ?',
///         binds: [...cmd.binds, tenantId],
///       );
///     }
///     return cmd;
///   }
/// }
///
/// class AuditLog extends DbInterceptor {
///   @override
///   Future<void> onSaveChangesStart(ChangeSet changes) async {
///     log.write('Saving ${changes.entries.length} changes...');
///   }
/// }
///
/// // Wire-up:
/// final db = await Db.open(url: '...', engine: const SqliteEngine());
/// db.context.interceptors
///   ..add(TenantFilter(42))
///   ..add(AuditLog());
/// ```
///
/// ## Engine-agnostic
///
/// The interceptor contract is engine-agnostic.
/// It lives in d_rocket core. The wire-up
/// (calling the interceptor at the right moment)
/// is in the core's DbContext/DbSet; the engine
/// does not need to know about interceptors at
/// all (it only sees the final SQL after all
/// interceptors have transformed it).
library;

import '../orm/change_tracker.dart';
import 'db_context.dart';
import 'entity_meta.dart';
import '../linq/i_queryable.dart';

/// A SELECT command about to be executed.
///
/// Interceptors receive a `QueryCommand` in
/// `onQuery`, can transform it (rewrite SQL,
/// add binds), and return the (possibly
/// modified) command. The actual `selectAsync`
/// call uses the returned command's SQL and
/// binds.
class QueryCommand {
  /// The SQL string (possibly with `?` placeholders
  /// for SQLite / `$N` for Postgres). Already
  /// translated by the engine's [SqlTranslator].
  final String sql;

  /// The bind values, one per `?` in [sql].
  final List<Object?> binds;

  /// The table being queried (e.g. `'user'`).
  /// Used by interceptors for routing decisions
  /// (e.g. "only add tenant filter to the
  /// `user` table").
  final String table;

  /// The DbSet's reader function (turns a
  /// row into a typed entity). Interceptors
  /// can use this to read the typed result,
  /// or to set up a different reader.
  final IQueryable Function()? _reader;

  QueryCommand({
    required this.sql,
    required this.binds,
    required this.table,
    IQueryable Function()? reader,
  }) : _reader = reader;

  /// A copy with optional field overrides.
  QueryCommand copyWith({
    String? sql,
    List<Object?>? binds,
    String? table,
  }) {
    return QueryCommand(
      sql: sql ?? this.sql,
      binds: binds ?? this.binds,
      table: table ?? this.table,
      reader: _reader,
    );
  }

  @override
  String toString() =>
      'QueryCommand(table: $table, sql: $sql, binds: $binds)';
}

/// The result of a SELECT. Interceptors receive
/// this in `onQueryComplete` (with `error: null`)
/// or with `error: <some exception>` (the query
/// failed).
class QueryResult {
  /// The (possibly post-processed) rows.
  /// Each row is a `Map<String, Object?>`.
  final List<Object?> rows;

  /// The original [QueryCommand] that produced
  /// this result. Useful for logging
  /// ("query X returned N rows in Y ms").
  final QueryCommand command;

  /// How long the underlying `selectAsync` took.
  /// Useful for slow-query logs.
  final Duration elapsed;

  /// The error if the query failed, null on
  /// success. Interceptors can re-throw,
  /// swallow, or transform errors.
  final Object? error;

  /// The stack trace if the query failed,
  /// null on success.
  final StackTrace? stackTrace;

  const QueryResult({
    required this.rows,
    required this.command,
    required this.elapsed,
    this.error,
    this.stackTrace,
  });

  /// True if the query succeeded.
  bool get isSuccess => error == null;

  @override
  String toString() => 'QueryResult('
      'rows: ${rows.length}, '
      'elapsed: ${elapsed.inMilliseconds}ms, '
      'error: ${error == null ? "none" : error.runtimeType})';
}

/// An INSERT / UPDATE / DELETE command about
/// to be executed. Same pattern as [QueryCommand]:
/// interceptors can transform SQL and binds.
class MutationCommand {
  final String sql;
  final List<Object?> binds;
  final String table;

  /// 'INSERT', 'UPDATE', or 'DELETE'.
  final String operation;

  /// The entity being mutated (for INSERT and
  /// UPDATE — null for bulk operations that
  /// don't carry a single entity).
  final Object? entity;

  const MutationCommand({
    required this.sql,
    required this.binds,
    required this.table,
    required this.operation,
    this.entity,
  });

  MutationCommand copyWith({
    String? sql,
    List<Object?>? binds,
    String? table,
    String? operation,
    Object? entity,
  }) {
    return MutationCommand(
      sql: sql ?? this.sql,
      binds: binds ?? this.binds,
      table: table ?? this.table,
      operation: operation ?? this.operation,
      entity: entity ?? this.entity,
    );
  }

  @override
  String toString() => 'MutationCommand('
      'table: $table, op: $operation, '
      'sql: $sql, binds: $binds)';
}

/// The result of a mutation. Interceptors
/// receive this in `onMutationComplete`.
class MutationResult {
  /// The number of rows affected (0, 1, or N).
  final int rowsAffected;

  /// The original [MutationCommand].
  final MutationCommand command;

  /// The ROWID of the inserted row (only
  /// meaningful for INSERTs that use
  /// `lastInsertRowIdAsync`; null for UPDATE /
  /// DELETE).
  final int? lastInsertRowId;

  /// How long the underlying `executeAsync` took.
  final Duration elapsed;

  /// The error if the mutation failed.
  final Object? error;
  final StackTrace? stackTrace;

  const MutationResult({
    required this.rowsAffected,
    required this.command,
    this.lastInsertRowId,
    required this.elapsed,
    this.error,
    this.stackTrace,
  });

  bool get isSuccess => error == null;

  @override
  String toString() => 'MutationResult('
      'op: ${command.operation}, '
      'rows: $rowsAffected, '
      'elapsed: ${elapsed.inMilliseconds}ms, '
      'error: ${error == null ? "none" : error.runtimeType})';
}

/// A snapshot of all changes about to be saved
/// (or just saved) by a single `saveChanges()`
/// call. Interceptors receive this in
/// `onSaveChangesStart` and `onSaveChangesEnd`.
///
/// This is the **entity-level** view (vs the
/// command-level view of [QueryCommand] /
/// [MutationCommand]). One `ChangeSet` can
/// contain N entries (one per Added / Modified /
/// Deleted entity).
class ChangeSet {
  /// The per-entity changes, in save order.
  final List<ChangeEntry> entries;

  /// The DbContext that produced this change set.
  /// Interceptors can use this to access the
  /// tracker or other context state.
  final DbContext context;

  /// Monotonic counter — increments per
  /// `saveChanges()` call. Useful for
  /// correlating logs.
  final int batchId;

  const ChangeSet({
    required this.entries,
    required this.context,
    required this.batchId,
  });

  bool get isEmpty => entries.isEmpty;
  bool get isNotEmpty => entries.isNotEmpty;
  int get length => entries.length;
}

/// A single entity in a [ChangeSet] — the
/// interceptor's view of one row about to be
/// INSERTed / UPDATEd / DELETEd.
class ChangeEntry {
  /// The entity state: [EntityState.added],
  /// [EntityState.modified], or
  /// [EntityState.deleted].
  final EntityState state;

  /// The entity itself.
  final Object entity;

  /// The [EntityMeta] (table name, columns).
  /// Read from the DbSet's entity meta.
  final EntityMeta meta;

  /// The change tracker event (for access to
  /// original values, etc.). Null for
  /// `onEntitySaving` of brand-new entities
  /// (no "original" yet).
  final ChangeEvent? event;

  /// The mutation command that will be /
  /// was executed for this entity. Null
  /// before the SQL is built; set during
  /// saveChanges's INSERT / UPDATE / DELETE
  /// step.
  final MutationCommand? command;

  const ChangeEntry({
    required this.state,
    required this.entity,
    required this.meta,
    this.event,
    this.command,
  });
}

/// The base class for ORM interceptors.
///
/// Override only the methods you care about.
/// All methods have a default no-op
/// implementation (return the input
/// unchanged, or do nothing for void
/// methods).
///
/// The interceptor chain is invoked in
/// registration order. To abort an
/// operation, throw an exception (the
/// exception propagates to the user code
/// that called `toListAsync_` /
/// `saveChanges`).
abstract class DbInterceptor {
  const DbInterceptor();

  // ─── Query path (SELECT) ─────────────────────────

  /// Called before a SELECT is executed.
  /// Can rewrite the SQL / binds, or throw
  /// to abort the query.
  Future<QueryCommand> onQuery(QueryCommand cmd) async => cmd;

  /// Called after a SELECT completes (success
  /// or error). Can inspect / modify the
  /// result, log, or transform errors.
  Future<QueryResult> onQueryComplete(QueryResult result) async => result;

  // ─── Mutation path (INSERT / UPDATE / DELETE) ────

  /// Called before an INSERT / UPDATE / DELETE
  /// is executed. Can rewrite the SQL / binds
  /// (e.g. add `created_at`, encrypt a column,
  /// convert DELETE to soft-delete), or throw
  /// to abort.
  Future<MutationCommand> onMutation(MutationCommand cmd) async => cmd;

  /// Called after a mutation completes
  /// (success or error). Can log the affected
  /// rows, retry on deadlock, etc.
  Future<MutationResult> onMutationComplete(MutationResult result) async => result;

  // ─── saveChanges path ───────────────────────────

  /// Called at the start of `saveChanges()` —
  /// before any entity is saved. Receives the
  /// full [ChangeSet] so the interceptor can
  /// do global checks (validate invariants,
  /// reject the whole batch on first failure,
  /// set common fields on all entities, etc.).
  Future<void> onSaveChangesStart(ChangeSet changes) async {}

  /// Called per-entity, just before the
  /// INSERT / UPDATE / DELETE for that entity
  /// is sent. The interceptor can modify
  /// the entity itself (e.g. set
  /// `created_at = DateTime.now()` on a new
  /// entity, mark `deleted_at` instead of
  /// hard-deleting, validate field values).
  ///
  /// Note: this is the **last chance** to
  /// modify the entity before it's persisted.
  /// The mutation happens on the next
  /// `await` after this method returns.
  Future<void> onEntitySaving(ChangeEntry entry) async {}

  /// Called per-entity, just after the
  /// INSERT / UPDATE / DELETE for that entity
  /// is sent. The interceptor can inspect
  /// the result, log, or react to errors.
  ///
  /// If the entity save failed, [error] is
  /// non-null in the result; the interceptor
  /// can choose to swallow, rethrow, or
  /// transform.
  Future<void> onEntitySaved(ChangeEntry entry, MutationResult result) async {}

  /// Called at the end of `saveChanges()` —
  /// after all entities are saved (or after
  /// a failure). The interceptor can do
  /// global cleanup (publish events, send
  /// notifications, write audit log).
  Future<void> onSaveChangesEnd(ChangeSet changes, Object? error) async {}
}

/// Holds the ordered list of [DbInterceptor]s
/// for a [DbContext]. Interceptors are invoked
/// in insertion order.
class InterceptorRegistry {
  final List<DbInterceptor> _interceptors = <DbInterceptor>[];

  /// All registered interceptors, in order.
  List<DbInterceptor> get interceptors => List.unmodifiable(_interceptors);

  /// The number of registered interceptors.
  int get length => _interceptors.length;

  /// Whether any interceptors are registered.
  bool get isEmpty => _interceptors.isEmpty;
  bool get isNotEmpty => _interceptors.isNotEmpty;

  /// Adds an interceptor to the end of the chain.
  void add(DbInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  /// Adds multiple interceptors to the end of
  /// the chain, in the given order.
  void addAll(Iterable<DbInterceptor> interceptors) {
    _interceptors.addAll(interceptors);
  }

  /// Removes a previously-added interceptor.
  /// Returns true if the interceptor was found
  /// and removed.
  bool remove(DbInterceptor interceptor) {
    return _interceptors.remove(interceptor);
  }

  /// Clears all interceptors.
  void clear() {
    _interceptors.clear();
  }
}
