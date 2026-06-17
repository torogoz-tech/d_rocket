// Tests for the engine registry (Phase 1 of the
// 2.0.0 multi-engine architecture).
//
// The EngineRegistry is the static slot that
// holds the active DbEngine. The Db.open factory
// delegates to it. In Phase 1, the registry
// auto-registers the in-core SQLite engine when
// no engine is set; Phase 2 removes that
// fallback.
//
// These tests verify:
//   1. register + findOrThrow round-trip.
//   2. findOrThrow auto-registers the SQLite
//      engine when called the first time.
//   3. resetForTest clears the slot.
//   4. SqliteEngine.open returns an
//      AsyncQueryProvider (in-memory and file).
//   5. SqliteEngine.isAvailable returns true on
//      a host with libsqlite3 loadable.
//   6. DatabaseException includes the new fields
//      (sql, code) and toString() is readable.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

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
    EncryptionConfig? encryptionConfig,
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

    test('findOrThrow auto-registers the SQLite engine the first time', () {
      // The registry is empty at the start (set by
      // tearDown via resetForTest).
      expect(EngineRegistry.isRegistered, isFalse);
      final engine = EngineRegistry.findOrThrow;
      // The auto-registration inserts the in-core
      // SQLite engine.
      expect(engine, isA<SqliteEngine>());
      expect(engine.name, equals('sqlite'));
      expect(EngineRegistry.isRegistered, isTrue);
      // The second call does not replace it.
      expect(EngineRegistry.findOrThrow, same(engine));
    });

    test('resetForTest clears the registry', () {
      EngineRegistry.register(_StubEngine('temp'));
      expect(EngineRegistry.isRegistered, isTrue);
      EngineRegistry.resetForTest();
      expect(EngineRegistry.isRegistered, isFalse);
    });
  });

  group('SqliteEngine', () {
    test('name is "sqlite"', () {
      expect(const SqliteEngine().name, equals('sqlite'));
    });

    test('isAvailable is true on a host with libsqlite3', () {
      // The test environment always has sqlite3
      // available. If this fails, the platform is
      // not supported (the engine itself will
      // throw at open() time).
      expect(const SqliteEngine().isAvailable, isTrue);
    });

    test('open with no path returns an in-memory provider', () async {
      final AsyncQueryProvider p = await const SqliteEngine().open();
      expect(p, isA<AsyncQueryProvider>());
      expect(p.isOpen, isTrue);
      await p.disposeAsync();
      expect(p.isOpen, isFalse);
    });

    test('open with ":memory:" path returns an in-memory provider', () async {
      final AsyncQueryProvider p = await const SqliteEngine().open(
        path: ':memory:',
      );
      expect(p.isOpen, isTrue);
      await p.disposeAsync();
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
