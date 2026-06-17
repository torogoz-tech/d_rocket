/// The in-core SQLite engine for d_rocket.
///
/// In Phase 1, this engine lives inside
/// `d_rocket` itself, so consumers don't need
/// any extra package. `Db.open(path: 'app.db')`
/// "just works" without an explicit engine
/// registration call.
///
/// In Phase 2, this engine moves to a
/// separate `d_rocket_engine_sqlite` package.
/// The `d_rocket` package no longer depends on
/// `package:sqlite3` directly. The dev adds
/// `d_rocket_engine_sqlite` to their pubspec and
/// calls `d_rocket_engine_sqlite.register()`
/// before `Db.open` works. The migration story
/// is documented in the 2.0.0 release notes.
library;

import 'package:sqlite3/sqlite3.dart' as sql;

import 'async_query_provider.dart';
import 'db_engine.dart';
import 'engine_registry.dart';
import '../sqlite/encryption_config.dart';
import '../sqlite/query_provider.dart';

class SqliteEngine implements DbEngine {
  const SqliteEngine();

  @override
  String get name => 'sqlite';

  @override
  bool get isAvailable {
    try {
      // sqlite3's library load is lazy; a successful
      // version query is the cheapest way to verify
      // the native lib is loadable on this platform.
      sql.sqlite3.version;
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<AsyncQueryProvider> open({
    String? path,
    String? password,
    EncryptionConfig? encryptionConfig,
  }) async {
    final String? resolvedPath = path;
    if (resolvedPath == null || resolvedPath == ':memory:') {
      return SqliteQueryProvider.inMemory(
        password: password,
        encryptionConfig: encryptionConfig,
      );
    }
    return SqliteQueryProvider.file(
      resolvedPath,
      password: password,
      encryptionConfig: encryptionConfig,
    );
  }
}

/// Phase 1 helper: register the in-core SQLite
/// engine. This is what tests and apps that
/// don't yet use the explicit registration
/// pattern call. Phase 2 will move this to
/// `d_rocket_engine_sqlite` and the helper
/// here will be removed.
void registerDefaultEngine() {
  // EngineRegistry is in this same package; the
  // import is via the relative path.
  // ignore: avoid_relative_lib_imports
  EngineRegistry.register(const SqliteEngine());
}
