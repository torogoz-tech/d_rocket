/// The SQL dialect contract.
///
/// d_rocket's SQL operator layer lives in
/// d_rocket core (engine-agnostic). The
/// `Expr` tree → SQL translation is shared
/// across engines; the differences between
/// dialects (SQLite vs Postgres vs MySQL vs
/// …) are isolated in a [SqlDialect] that
/// each engine implements.
///
/// ## What the dialect controls
///
/// * **Placeholder format** — SQLite uses `?`,
///   Postgres uses `$1, $2, ...`. The
///   translator emits `?`; the dialect is
///   responsible for the on-the-wire format.
///   In practice, the translator emits `?`
///   and the `AsyncQueryProvider` rewrites
///   them to the engine-specific form
///   (PostgresQueryProvider does this; the
///   SQLite provider leaves them as-is).
/// * **`INSTR` vs `STRPOS`** — `String.contains`
///   translates to a substring search. SQLite
///   uses `INSTR(col, ?) > 0`; Postgres uses
///   `STRPOS(col, ?) > 0` (or `POSITION(? IN col) > 0`).
/// * **`json_object` vs `jsonb_build_object`** —
///   Map literals (the `@Embedded` map type)
///   translate to a JSON-construction function.
///   SQLite 3.38+ uses `json_object(...)`;
///   Postgres uses `jsonb_build_object(...)`.
///
/// ## Adding a new engine
///
/// To add a new engine (e.g. MySQL, MSSQL, Oracle),
/// implement [SqlDialect] and pass an instance
/// to the [SqlTranslator] constructor. The base
/// translator handles 95% of the operator tree
/// identically across engines; the dialect
/// captures the 5% that differ.
///
/// ## Status
///
/// This is the **2.0.0 dialect** abstraction.
/// It captures the differences the existing
/// SQLite engine and the new Postgres engine
/// need. Future dialects (MySQL, MSSQL) may
/// add more methods; backwards compatibility
/// is preserved by giving each new method a
/// default implementation that maps to the
/// "standard" SQL behaviour.
library;

/// The SQL dialect contract that each
/// d_rocket engine implements.
///
/// In d_rocket 2.0.0 this is an interface:
/// every method has a default implementation
/// (the "standard SQL" form), and engines
/// override the methods that differ. The
/// class is not `abstract` so it can be
/// instantiated directly (the default
/// dialect).
class SqlDialect {
  /// Const constructor so engines can
  /// pass `const SqlDialect()` /
  /// `const DefaultDialect()` /
  /// `const PostgresDialect()`.
  const SqlDialect();
  /// The placeholder format. By default,
  /// `?` (the SQL standard). Engines that
  /// use a different format (Postgres uses
  /// `$1, $2, ...`) can either:
  ///
  /// (a) override this method to return
  ///     a function that produces the
  ///     engine-specific form, or
  /// (b) rewrite the `?` placeholders in
  ///     the [AsyncQueryProvider] before
  ///     sending the SQL to the engine.
  ///
  /// The d_rocket 2.0.0 implementation
  /// uses approach (b) — the translator
  /// always emits `?` and the provider
  /// rewrites. This keeps the dialect
  /// surface small.
  String placeholder() => '?';

  /// The function name for `String.contains`.
  /// Returns the SQL function that returns
  /// the (1-based) position of the second
  /// argument in the first, or 0 if not
  /// found. The translator wraps this in
  /// `> 0` to produce a boolean.
  ///
  /// SQLite: `INSTR`.
  /// Postgres: `STRPOS` (or `POSITION`).
  /// MySQL: `LOCATE` (or `INSTR`).
  String stringContainsFunction() => 'INSTR';

  /// The function name for map-literal
  /// construction. The translator calls
  /// this with the (key1, value1, key2,
  /// value2, …) argument list.
  ///
  /// SQLite 3.38+: `json_object`.
  /// Postgres: `jsonb_build_object`.
  /// MySQL: `JSON_OBJECT`.
  String jsonObjectFunction() => 'json_object';
}

/// The default dialect (SQLite-flavoured).
///
/// `SqlTranslator`'s default constructor
/// uses this dialect. It is the same
/// behaviour as the 2.0.0 SQLite engine
/// (uses `INSTR` for `String.contains` and
/// `json_object` for map literals).
///
/// In d_rocket 2.0.0, the default dialect
/// IS the SQLite dialect. The Postgres
/// engine passes a [PostgresDialect] (in
/// d_rocket_engine_postgres) instead.
///
/// `DefaultDialect` is just a const alias
/// for [SqlDialect] (the default methods
/// are SQLite's). Engines pass
/// `const DefaultDialect()` to indicate
/// "give me the default behaviour" — it is
/// semantically the same as passing
/// `const SqlDialect()`.
class DefaultDialect extends SqlDialect {
  const DefaultDialect();
}
