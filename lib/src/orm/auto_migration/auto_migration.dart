// Public API barrel for the auto-migration system.
//
// Application code interacts with the auto-migration
// system via `Db.open(entityMetas: [...], autoMigrate:
// true)` and `db.pendingSchemaDiff()`. The
// `SchemaDiff` return type and the `AutoMigrationResult`
// return type are exposed here. The internal classes
// (`AutoMigrator`, `SchemaState`) are also exported
// because they appear in method signatures (e.g.
// `Db.runAutoMigrations()` returns `AutoMigrationResult`,
// and `computeSchemaDiff` is useful for advanced users
// who want to diff two snapshots outside the
// auto-migration flow).

export 'auto_migrator.dart' show AutoMigrator, AutoMigrationResult;
export 'schema_diff.dart'
    show
        computeSchemaDiff,
        DiffSeverity,
        SchemaDiff,
        SchemaOperationType;
export 'schema_snapshot.dart'
    show
        computeSnapshot,
        SchemaColumn,
        SchemaForeignKey,
        SchemaIndex,
        SchemaSnapshot,
        SchemaTable,
        columnToSnapshot,
        indexNameFor,
        sqliteTypeFor;
export 'schema_state.dart' show SchemaState, schemaStateTableDdl, schemaStateTableName;
