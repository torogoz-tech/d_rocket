// 2.0.0 — Tests for the `migration add` codegen
// path (Phase 8.11).
//
// The pure helpers live in
// `package:d_rocket/src/cli/migration_codegen.dart`.
// The CLI orchestration (worker spawn, file
// write) is covered by the existing
// `migration_check_test.dart` golden tests
// plus a manual smoke test that runs the
// binary end-to-end (documented in
// `doc/MIGRATION_LEGACY_TO_d_rocket.md`).
//
// We cover:
// - `CliSchemaDiff.fromJson` round-trips
//   the worker JSON shape.
// - `partitionDiffsBySeverity` sorts safe /
//   unsafe correctly.
// - `inverseSqlFor` returns the natural
//   inverse for safe ops and null for
//   unsafe ones.
// - `dartRawString` escapes `'''`.
// - `buildMigrationFileContent` produces
//   a valid Dart file with the right
//   class name, id, and pre-populated
//   `up()` / `down()`.
// - `cliNameToClassName` / `cliNameToFileName`
//   convert kebab/snake to PascalCase /
//   snake_case.

import 'package:d_rocket/src/cli/migration_codegen.dart';
import 'package:test/test.dart';

void main() {
  group('Phase 8.11 — CliSchemaDiff.fromJson', () {
    test('round-trips the worker JSON shape', () {
      final json = <String, Object?>{
        'severity': 'safe',
        'type': 'createTable',
        'tableName': 'users',
        'sql': 'CREATE TABLE users (id INTEGER PRIMARY KEY)',
        'reason': 'new entity',
      };
      final d = CliSchemaDiff.fromJson(json);
      expect(d.severity, equals('safe'));
      expect(d.type, equals('createTable'));
      expect(d.tableName, equals('users'));
      expect(d.columnName, isNull);
      expect(d.newColumnName, isNull);
      expect(d.sql, contains('CREATE TABLE'));
      expect(d.reason, equals('new entity'));
    });

    test('preserves column / newColumnName for column ops', () {
      final json = <String, Object?>{
        'severity': 'safe',
        'type': 'addColumn',
        'tableName': 'patients',
        'columnName': 'note',
        'sql': 'ALTER TABLE patients ADD COLUMN note TEXT',
        'reason': 'new field',
      };
      final d = CliSchemaDiff.fromJson(json);
      expect(d.columnName, equals('note'));
      expect(d.newColumnName, isNull);
    });

    test('defaults missing fields safely', () {
      final d = CliSchemaDiff.fromJson(<String, Object?>{});
      expect(d.severity, equals('unsafe'));
      expect(d.type, equals('unknown'));
      expect(d.tableName, equals('<unknown>'));
      expect(d.columnName, isNull);
      expect(d.sql, isEmpty);
    });
  });

  group('Phase 8.11 — partitionDiffsBySeverity', () {
    test('empty input → empty lists', () {
      final r = partitionDiffsBySeverity(<CliSchemaDiff>[]);
      expect(r.safe, isEmpty);
      expect(r.unsafe, isEmpty);
    });

    test('separates by severity, preserves order', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createTable',
            tableName: 'a',
            sql: 'x',
            reason: 'r'),
        const CliSchemaDiff(
            severity: 'unsafe',
            type: 'dropTable',
            tableName: 'b',
            sql: 'y',
            reason: 'r'),
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createIndex',
            tableName: 'a',
            columnName: 'ix_a',
            sql: 'z',
            reason: 'r'),
      ];
      final r = partitionDiffsBySeverity(diffs);
      expect(r.safe, hasLength(2));
      expect(r.safe[0].tableName, equals('a'));
      expect(r.safe[1].columnName, equals('ix_a'));
      expect(r.unsafe, hasLength(1));
      expect(r.unsafe.first.tableName, equals('b'));
    });
  });

  group('Phase 8.11 — inverseSqlFor', () {
    test('createTable → DROP TABLE', () {
      const d = CliSchemaDiff(
          severity: 'safe',
          type: 'createTable',
          tableName: 'users',
          sql: 'x',
          reason: 'r');
      expect(inverseSqlFor(d), equals('DROP TABLE users'));
    });

    test('createIndex → DROP INDEX <name>', () {
      const d = CliSchemaDiff(
          severity: 'safe',
          type: 'createIndex',
          tableName: 'users',
          columnName: 'ix_users_name',
          sql: 'x',
          reason: 'r');
      expect(inverseSqlFor(d),
          equals('DROP INDEX ix_users_name'));
    });

    test('createIndex without a name → null', () {
      const d = CliSchemaDiff(
          severity: 'safe',
          type: 'createIndex',
          tableName: 'users',
          sql: 'x',
          reason: 'r');
      expect(inverseSqlFor(d), isNull);
    });

    test('addColumn → ALTER TABLE DROP COLUMN', () {
      const d = CliSchemaDiff(
          severity: 'safe',
          type: 'addColumn',
          tableName: 'patients',
          columnName: 'note',
          sql: 'x',
          reason: 'r');
      expect(inverseSqlFor(d),
          equals('ALTER TABLE patients DROP COLUMN note'));
    });

    test('unsafe ops → null (no clean inverse)', () {
      const dropTable = CliSchemaDiff(
          severity: 'unsafe',
          type: 'dropTable',
          tableName: 'a',
          sql: 'x',
          reason: 'r');
      const dropCol = CliSchemaDiff(
          severity: 'unsafe',
          type: 'dropColumn',
          tableName: 'a',
          columnName: 'b',
          sql: 'x',
          reason: 'r');
      const modify = CliSchemaDiff(
          severity: 'unsafe',
          type: 'modifyColumn',
          tableName: 'a',
          columnName: 'b',
          sql: 'x',
          reason: 'r');
      const rename = CliSchemaDiff(
          severity: 'unsafe',
          type: 'renameColumn',
          tableName: 'a',
          columnName: 'old',
          newColumnName: 'new',
          sql: 'x',
          reason: 'r');
      expect(inverseSqlFor(dropTable), isNull);
      expect(inverseSqlFor(dropCol), isNull);
      expect(inverseSqlFor(modify), isNull);
      expect(inverseSqlFor(rename), isNull);
    });
  });

  group('Phase 8.11 — dartRawString', () {
    test('wraps the input in r\'\'\'...\'\'\'', () {
      expect(dartRawString('CREATE TABLE x'),
          equals("r'''CREATE TABLE x'''"));
    });

    test('escapes embedded triple-quotes', () {
      // Input `a'''b` should become
      // `r'''a\'\'\'b'''` (each `'''`
      // inside the raw string is escaped
      // to `\'\'\'`).
      expect(dartRawString("a'''b"),
          equals(r"r'''a\'\'\'b'''"));
    });
  });

  group('Phase 8.11 — buildMigrationFileContent', () {
    test('emits the class header with id and name', () {
      final src = buildMigrationFileContent(
        className: 'M003FooBar',
        id: '003',
        name: 'foo_bar',
        diffs: const <CliSchemaDiff>[],
      );
      expect(src, contains('class M003FooBar extends MigrationBase'));
      expect(src, contains("String get id => '003'"));
      expect(src, contains("String get name => 'foo_bar'"));
    });

    test('emits no-diff placeholder when diffs are empty', () {
      final src = buildMigrationFileContent(
        className: 'M003',
        id: '003',
        name: 'x',
        diffs: const <CliSchemaDiff>[],
      );
      expect(src, contains('No safe diffs detected at scaffold time'));
    });

    test('emits safe diffs in up() and inverse in down()', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createTable',
            tableName: 'users',
            sql: 'CREATE TABLE users (id INT)',
            reason: 'new'),
        const CliSchemaDiff(
            severity: 'safe',
            type: 'addColumn',
            tableName: 'patients',
            columnName: 'note',
            sql: 'ALTER TABLE patients ADD COLUMN note TEXT',
            reason: 'new'),
      ];
      final src = buildMigrationFileContent(
        className: 'M001',
        id: '001',
        name: 'init',
        diffs: diffs,
      );
      // `up()` body
      expect(src, contains('CREATE TABLE users (id INT)'));
      expect(src,
          contains('ALTER TABLE patients ADD COLUMN note TEXT'));
      // `down()` body (destructive — wrapped in
      // BEGIN/ROLLBACK guard)
      expect(src, contains('DROP TABLE users'));
      expect(src,
          contains('ALTER TABLE patients DROP COLUMN note'));
      expect(src, contains('exec("BEGIN;")'));
      expect(src, contains('exec("ROLLBACK;")'));
    });

    test('excludes unsafe diffs from up() by default', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createTable',
            tableName: 'a',
            sql: 'CREATE TABLE a (id INT)',
            reason: 'r'),
        const CliSchemaDiff(
            severity: 'unsafe',
            type: 'dropTable',
            tableName: 'b',
            sql: 'DROP TABLE b',
            reason: 'r'),
      ];
      final src = buildMigrationFileContent(
        className: 'M001',
        id: '001',
        name: 'x',
        diffs: diffs,
      );
      expect(src, contains('CREATE TABLE a (id INT)'));
      expect(src, isNot(contains('DROP TABLE b')));
      // ...but the unsafe diff is listed in
      // the comment header.
      expect(src, contains('UNSAFE diffs (NOT auto-applied)'));
      expect(src, contains('dropTable b'));
    });

    test('includes unsafe diffs in up() when includeUnsafe is true', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'unsafe',
            type: 'dropTable',
            tableName: 'b',
            sql: 'DROP TABLE b',
            reason: 'r'),
      ];
      final src = buildMigrationFileContent(
        className: 'M001',
        id: '001',
        name: 'x',
        diffs: diffs,
        options: const CodegenOptions(includeUnsafe: true),
      );
      expect(src, contains('DROP TABLE b'));
    });

    test('irreversible option skips the auto-inverse in down()', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createTable',
            tableName: 'a',
            sql: 'CREATE TABLE a (id INT)',
            reason: 'r'),
      ];
      final src = buildMigrationFileContent(
        className: 'M001',
        id: '001',
        name: 'x',
        diffs: diffs,
        options: const CodegenOptions(irreversible: true),
      );
      expect(src, isNot(contains('DROP TABLE a')));
      expect(src, contains('UnsupportedError'));
    });

    test('lists safe and unsafe counts in the comment header', () {
      final diffs = <CliSchemaDiff>[
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createTable',
            tableName: 'a',
            sql: 'x',
            reason: 'r'),
        const CliSchemaDiff(
            severity: 'safe',
            type: 'createIndex',
            tableName: 'a',
            columnName: 'ix',
            sql: 'x',
            reason: 'r'),
        const CliSchemaDiff(
            severity: 'unsafe',
            type: 'dropTable',
            tableName: 'b',
            sql: 'x',
            reason: 'r'),
      ];
      final src = buildMigrationFileContent(
        className: 'M001',
        id: '001',
        name: 'x',
        diffs: diffs,
      );
      expect(src, contains('Forward operations: 2 safe, 1 unsafe'));
    });
  });

  group('Phase 8.11 — cliNameToClassName / cliNameToFileName', () {
    test('snake_case to PascalCase with id prefix', () {
      expect(
        cliNameToClassName(cliName: 'add_note_to_patients', id: '003'),
        equals('M003AddNoteToPatients'),
      );
    });

    test('kebab-case to PascalCase', () {
      expect(
        cliNameToClassName(cliName: 'add-note-to-patients', id: '005'),
        equals('M005AddNoteToPatients'),
      );
    });

    test('single word', () {
      expect(
        cliNameToClassName(cliName: 'init', id: '001'),
        equals('M001Init'),
      );
    });

    test('file name is snake_case', () {
      expect(cliNameToFileName('add-note-to-patients'),
          equals('add_note_to_patients'));
      expect(cliNameToFileName('AddNoteToPatients'),
          equals('addnotetopatients'));
      expect(cliNameToFileName('init'), equals('init'));
    });
  });
}
