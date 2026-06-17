// .2c (split): barrel for the ORM runtime.
// The codegen (`d_rocket_builder`) emits the
// per-class `*.d_rocket_orm.g.dart` parts and the
// central `d_rocket_registry.g.dart` (with
// `initializeD`) that calls
// `register<X>EntityMeta` for every `@Table`
// class.

export 'async_migration_executor.dart';
export 'async_migration_selector.dart';
export 'async_query_provider.dart';
export 'bulk_ops.dart';
export 'change_tracker.dart';
export 'column.dart';
export 'column_meta.dart';
export 'database_exception.dart';
export 'db_engine.dart';
export 'db_set.dart';
export 'db_set_include.dart';
export 'embedded.dart';
export 'embedded_meta.dart';
export 'engine_registry.dart';
export 'navigation_meta.dart';
export 'navigation_populator.dart';
export 'navigation_registry.dart';
export 'entity_meta.dart';
export 'entity_registry.dart';
export 'foreign_key.dart';
// `include_relation.dart` is a `part`-style library
// (its subtypes are in `part of` files) — we only
// need to export the parent.
export 'include_relation.dart';
export 'index.dart';
export 'inheritance_strategy.dart';
export 'applied_migration.dart';
export 'migration.dart';
export 'migration_annotation.dart';
export 'migration_executor.dart';
export 'migration_runner.dart';
export 'migration_selector.dart';
export 'migration_strategy.dart';
export 'on_delete_action.dart';
export 'primary_key.dart';
export 'db_context.dart';
export 'table.dart';
export 'tracked_entry.dart';

// `sqlite_engine.dart` is exported here so the
// in-core SQLite engine is reachable via
// `package:d_rocket/d_rocket.dart`. Phase 2 will
// move this file to the `d_rocket_engine_sqlite`
// package and the export will be removed.
export 'sqlite_engine.dart';
