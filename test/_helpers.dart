// Shared test helpers for d_rocket tests that
// need a real database engine.
//
// The d_rocket core package is engine-agnostic.
// Tests that exercise the ORM runtime against a
// real engine use the SQLite engine from
// d_rocket_engine_sqlite (the only engine that
// ships in 2.0 with native bindings on macOS,
// Linux, and Windows — the test environment).
//
// Importing this file also re-exports both
// d_rocket (the engine-agnostic core) and the
// engine-specific types from
// d_rocket_engine_sqlite, so a test can do:
//
// ```dart
// import '../_helpers.dart';
//
// void main() {
//   setUp(dRocketSqlite);
//   test('something', () async {
//     final ctx = MyContext();
//     final provider = SqliteQueryProvider.inMemory();
//     // ...
//   });
// }
// ```
library;

import 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';
import 'package:test/test.dart';

export 'package:d_rocket/d_rocket.dart';
export 'package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart';

/// Registers the SQLite engine. Call this from
/// your test's `setUp` (or `setUpAll` if you
/// don't reset between tests).
void setUpSqlite({bool resetBetweenTests = true}) {
  setUpAll(() {
    dRocketSqlite();
  });
  if (resetBetweenTests) {
    tearDown(() {
      EngineRegistry.resetForTest();
      dRocketSqlite();
    });
  }
}
