/// Engine registry for the db-agnostic ORM.
///
/// A single static slot that holds the currently
/// registered [DbEngine]. The `Db.open(...)` factory
/// (in `d_rocket_engine_sqlite`) looks up the engine
/// from this registry and delegates the actual
/// database work to it.
///
/// ## Phase 2: explicit registration
///
/// In 2.0 the registry no longer auto-registers
/// an engine. The dev must call
/// `d_rocket_engine_sqlite.register()`
/// (or another `d_rocket_engine_*.register()`)
/// once at app startup, before `Db.open` /
/// `Db.inMemory` is called. Without the call,
/// `findOrThrow` raises a `StateError` with a
/// clear "add an engine package to your pubspec
/// and call `register()`" message.
///
/// ```dart
/// void main() async {
///   d_rocket_engine_sqlite.register();
///   initializeD();
///   final db = await Db.open(path: 'app.db');
/// }
/// ```
library;

import 'package:meta/meta.dart';

import 'db_engine.dart';

class EngineRegistry {
  EngineRegistry._();

  static DbEngine? _engine;

  /// Register a [DbEngine] as the active engine.
  ///
  /// Calling this replaces any previously registered
  /// engine. The dev can swap engines between
  /// databases (test environment vs production, or
  /// the dev override for a specific test case).
  ///
  /// Idempotent across calls: only one engine is
  /// active at a time. The most recent call wins.
  static void register(DbEngine engine) {
    _engine = engine;
  }

  /// Look up the registered engine.
  ///
  /// Throws a [StateError] with an actionable
  /// message if no engine is registered. The
  /// message points the dev at
  /// `d_rocket_engine_sqlite.register()` (or
  /// another engine's `register()`) and lists
  /// the engine packages that ship in 2.0.
  static DbEngine get findOrThrow {
    final DbEngine? engine = _engine;
    if (engine == null) {
      throw StateError(
        'No d_rocket DbEngine registered. Add a '
        'd_rocket_engine_* package to your pubspec '
        '(d_rocket_engine_sqlite, '
        'd_rocket_engine_postgres, or '
        'd_rocket_engine_libsql_wasm) and call its '
        'register() once at app startup, before any '
        'Db.open / Db.inMemory call. See '
        'https://github.com/torogoz-tech/d_rocket '
        'for the engine selection guide.',
      );
    }
    return engine;
  }

  /// Test helper: reset the registry to empty.
  ///
  /// After this, the next `findOrThrow` will throw
  /// the "no engine registered" `StateError` until
  /// the test calls [register] again.
  @visibleForTesting
  static void resetForTest() {
    _engine = null;
  }

  /// Returns true if an engine is currently
  /// registered. Useful for tests and for the
  /// README's "modular dep" section.
  static bool get isRegistered => _engine != null;
}
