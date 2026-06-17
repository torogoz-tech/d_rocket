// Tests for the engine registry (Phase 2 of the
// 2.0.0 multi-engine architecture).
//
// The EngineRegistry is the static slot that
// holds the active DbEngine. The Db.open factory
// (in d_rocket_engine_sqlite) delegates to it.
// In Phase 2 the registry no longer auto-
// registers an engine — it throws a clear
// StateError with a pointer to
// `d_rocket_engine_sqlite.register()`.
//
// These tests verify:
//   1. register + findOrThrow round-trip.
//   2. register replaces a previously registered
//      engine.
//   3. findOrThrow throws a StateError with a
//      pointer to the engine packages when no
//      engine is registered.
//   4. resetForTest clears the slot.
//   5. DatabaseException includes the fields
//      (sql, code, cause) and toString() is
//      readable.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../_helpers.dart';

class _StubEngine implements DbEngine {
  _StubEngine(this._name);
  final String _name;
  int openCount = 0;

  @override
  String get name => _name;

  @override
  bool get isAvailable => true;

  @override
  Future<AsyncQueryProvider> open({
    String? path,
    String? password,
    Object? encryptionConfig,
  }) async {
    openCount++;
    throw UnimplementedError('stub engine never opens for real');
  }
}

void main() {
  group('EngineRegistry', () {
    tearDown(() {
      EngineRegistry.resetForTest();
    });

    test('is empty at start', () {
      expect(EngineRegistry.isRegistered, isFalse);
    });

    test('register + findOrThrow round-trip', () {
      final stub = _StubEngine('stub-a');
      EngineRegistry.register(stub);
      expect(EngineRegistry.isRegistered, isTrue);
      expect(EngineRegistry.findOrThrow, same(stub));
    });

    test('register replaces a previously registered engine', () {
      EngineRegistry.register(_StubEngine('first'));
      final second = _StubEngine('second');
      EngineRegistry.register(second);
      expect(EngineRegistry.findOrThrow, same(second));
    });

    test(
      'findOrThrow throws a StateError with an actionable message when no '
      'engine is registered',
      () {
        expect(EngineRegistry.isRegistered, isFalse);
        Object? caught;
        try {
          EngineRegistry.findOrThrow;
        } catch (e) {
          caught = e;
        }
        expect(caught, isA<StateError>());
        final String message = caught.toString();
        expect(message, contains('d_rocket_engine_sqlite'));
        expect(message, contains('d_rocket_engine_postgres'));
        expect(message, contains('d_rocket_engine_libsql_wasm'));
        expect(message, contains('register()'));
      },
    );

    test('resetForTest clears the registry', () {
      EngineRegistry.register(_StubEngine('temp'));
      expect(EngineRegistry.isRegistered, isTrue);
      EngineRegistry.resetForTest();
      expect(EngineRegistry.isRegistered, isFalse);
    });
  });

  group('DatabaseException', () {
    test('constructor with just a message', () {
      final e = DatabaseException('boom');
      expect(e.message, equals('boom'));
      expect(e.cause, isNull);
      expect(e.sql, isNull);
      expect(e.code, isNull);
    });

    test('constructor with cause', () {
      final cause = StateError('inner');
      final e = DatabaseException('boom', cause: cause);
      expect(e.cause, same(cause));
    });

    test('constructor with sql and code', () {
      final e = DatabaseException(
        'constraint failed',
        sql: 'INSERT INTO t (x) VALUES (1)',
        code: 787,
      );
      expect(e.sql, contains('INSERT INTO t'));
      expect(e.code, equals(787));
    });

    test('toString includes the message', () {
      final e = DatabaseException('boom');
      expect(e.toString(), contains('boom'));
    });

    test('toString includes the cause when present', () {
      final e = DatabaseException('boom', cause: StateError('inner'));
      expect(e.toString(), contains('cause:'));
      expect(e.toString(), contains('inner'));
    });
  });
}
