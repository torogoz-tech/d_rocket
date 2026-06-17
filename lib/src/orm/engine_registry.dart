/// Engine registry for the db-agnostic ORM.
///
/// Phase 1 introduces the [EngineRegistry]: a single
/// static slot that holds the currently registered
/// [DbEngine]. The `Db.open(...)` factory looks up
/// the engine from this registry and delegates the
/// actual database work to it.
///
/// In Phase 1, the registry is empty by default.
/// The first time `Db.open` is called and the
/// registry is empty, the in-core SQLite engine
/// (see [SqliteEngine] in `lib/src/orm/sqlite_engine.dart`)
/// is auto-registered. This preserves the 1.x
/// "just call Db.open and it works" experience
/// while preparing the cutover to Phase 2.
///
/// In Phase 2, the SQLite engine moves to a
/// separate `d_rocket_engine_sqlite` package,
/// the auto-registration is removed, and the
/// dev must call `d_rocket_engine_sqlite.register()`
/// explicitly before `Db.open` works.
library;

import 'package:meta/meta.dart';

import 'db_engine.dart';
import 'sqlite_engine.dart';

class EngineRegistry {
  EngineRegistry._();

  static DbEngine? _engine;
  static bool _autoRegistered = false;

  /// Register a [DbEngine] as the active engine.
  ///
  /// Calling this replaces any previously registered
  /// engine. The dev can swap engines between
  /// databases (test environment vs production, or
  /// the dev override for a specific test case).
  static void register(DbEngine engine) {
    _engine = engine;
  }

  /// Look up the registered engine.
  ///
  /// If no engine is registered, the in-core SQLite
  /// engine is auto-registered (Phase 1 only). This
  /// preserves the 1.x behavior where `Db.open`
  /// "just works" without any setup call.
  ///
  /// Phase 2 removes the auto-registration: if no
  /// engine is registered, this getter throws a
  /// `StateError` with a clear "add an engine
  /// package to your pubspec and call
  /// register()" message.
  static DbEngine get findOrThrow {
    if (_engine != null) return _engine!;
    if (!_autoRegistered) {
      // Phase 1 fallback: auto-register the in-core
      // SQLite engine. Phase 2 will replace this
      // with a StateError.
      register(const SqliteEngine());
      _autoRegistered = true;
    }
    return _engine!;
  }

  /// Test helper: reset the registry to empty.
  ///
  /// Use this in tests to verify the "no engine
  /// registered → throws" path (after Phase 2
  /// ships). In Phase 1, calling this and then
  /// `Db.open` will trigger the auto-registration
  /// again, which is the expected behavior.
  @visibleForTesting
  static void resetForTest() {
    _engine = null;
    _autoRegistered = false;
  }

  /// Returns true if an engine is currently
  /// registered. Useful for tests and for the
  /// README's "modular dep" section.
  static bool get isRegistered => _engine != null;
}
