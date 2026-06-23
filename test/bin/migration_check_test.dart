// Tests for `bin/migration.dart check` (Fase 11a).
//
// The CLI's `check` subcommand:
// 1. Parses `--db <path>` + `--entities <dart_file>`.
// 2. Validates the entities file (exists, exports
//    `entityMetas`).
// 3. Writes a temp worker under `.d_rocket/`
//    and runs `dart run` on it.
// 4. Parses the JSON between `DR_CHECK_JSON_BEGIN` /
//    `DR_CHECK_JSON_END` markers.
// 5. Prints a summary + exits 1 on unsafe diffs.
//
// The tests below cover:
// - Flag parsing (`--db`, `--target`, `--entities`, `-e`).
// - Error paths (`--db` missing, `--entities` missing,
//   entities file does not exist, entities file lacks
//   `entityMetas`).
// - The worker source template (must contain the
//   right imports + the JSON markers).
// - The JSON extraction logic (between markers).
//
// We do NOT spawn `dart run` in the unit tests;
// the subprocess path is covered by manual smoke
// tests + the SQLite engine's own AutoMigrator
// tests (in
// `test/orm/auto_migration/auto_migrator_e2e_test.dart`).

import 'dart:convert';
import 'dart:io';

import 'package:d_rocket/src/cli/migration_check.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 11a — `migration check` flag parsing', () {
    test('extracts --db', () {
      final f = parseCheckFlags(<String>['--db', 'app.db']);
      expect(f.dbPath, equals('app.db'));
      expect(f.entitiesFile, isNull);
      expect(f.target, isNull);
    });

    test('extracts --entities', () {
      final f = parseCheckFlags(
        <String>['--db', 'app.db', '--entities', 'lib/db/entities.dart'],
      );
      expect(f.dbPath, equals('app.db'));
      expect(f.entitiesFile, equals('lib/db/entities.dart'));
    });

    test('--entities short form -e works', () {
      final f = parseCheckFlags(
        <String>['--db', 'app.db', '-e', 'lib/entities.dart'],
      );
      expect(f.entitiesFile, equals('lib/entities.dart'));
    });

    test('extracts --target', () {
      final f = parseCheckFlags(
        <String>['--db', 'app.db', '--target', '5'],
      );
      expect(f.target, equals(5));
    });

    test('unknown flags are ignored', () {
      final f = parseCheckFlags(
        <String>['--db', 'app.db', '--unknown', 'x'],
      );
      expect(f.dbPath, equals('app.db'));
    });
  });

  group('Fase 11a — check worker source', () {
    test('contains the JSON begin/end markers', () {
      final src = buildCheckWorkerSource('lib/db/entities.dart');
      expect(src, contains('DR_CHECK_JSON_BEGIN'));
      expect(src, contains('DR_CHECK_JSON_END'));
    });

    test('imports the entities file the user passed', () {
      final src = buildCheckWorkerSource('lib/db/my_entities.dart');
      expect(src, contains("import 'lib/db/my_entities.dart'"));
      expect(src, contains('user_entities.entityMetas'));
    });

    test('imports d_rocket and the SQLite engine', () {
      final src = buildCheckWorkerSource('lib/db/entities.dart');
      expect(src, contains("package:d_rocket/d_rocket.dart"));
      expect(src,
          contains('package:d_rocket_engine_sqlite/d_rocket_engine_sqlite.dart'));
      expect(src, contains('AutoMigrator'));
      expect(src, contains('SqliteQueryProvider'));
      expect(src, contains('computePendingDiff'));
    });

    test('emits JSON via jsonEncode', () {
      final src = buildCheckWorkerSource('lib/db/entities.dart');
      expect(src, contains('jsonEncode'));
    });

    test('exits with code 3 on uncaught error', () {
      final src = buildCheckWorkerSource('lib/db/entities.dart');
      expect(src, contains('exit(3)'));
    });

    test('emits one entry per diff with the documented keys', () {
      final src = buildCheckWorkerSource('lib/db/entities.dart');
      expect(src, contains("'severity'"));
      expect(src, contains("'type'"));
      expect(src, contains("'tableName'"));
      expect(src, contains("'sql'"));
      expect(src, contains("'reason'"));
    });
  });

  group('Fase 11a — JSON extraction', () {
    test('extracts a clean payload between the markers', () {
      final src = '''
        some leading noise from the dart vm
        DR_CHECK_JSON_BEGIN
        [{"severity":"safe","type":"createTable","tableName":"users","sql":"CREATE TABLE users","reason":"new entity"}]
        DR_CHECK_JSON_END
        trailing noise
      ''';
      final List<dynamic> parsed = extractCheckJsonPayload(src);
      expect(parsed, hasLength(1));
      final first = parsed.first as Map;
      expect(first['severity'], equals('safe'));
      expect(first['type'], equals('createTable'));
      expect(first['tableName'], equals('users'));
    });

    test('extracts multiple entries', () {
      final payload = <Map<String, Object?>>[
        <String, Object?>{
          'severity': 'safe',
          'type': 'createTable',
          'tableName': 'a',
          'sql': 'CREATE TABLE a',
          'reason': 'new',
        },
        <String, Object?>{
          'severity': 'unsafe',
          'type': 'dropTable',
          'tableName': 'b',
          'sql': 'DROP TABLE b',
          'reason': 'data loss',
        },
      ];
      final src = 'noise\nDR_CHECK_JSON_BEGIN\n'
          '${jsonEncode(payload)}\nDR_CHECK_JSON_END\nmore noise';
      final List<dynamic> parsed = extractCheckJsonPayload(src);
      expect(parsed, hasLength(2));
    });

    test('returns an empty list when no diffs (empty JSON array)', () {
      final src = 'DR_CHECK_JSON_BEGIN\n[]\nDR_CHECK_JSON_END';
      expect(extractCheckJsonPayload(src), isEmpty);
    });

    test('throws FormatException on missing begin marker', () {
      expect(
        () => extractCheckJsonPayload('no markers here'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on missing end marker', () {
      expect(
        () => extractCheckJsonPayload(
          'DR_CHECK_JSON_BEGIN\n[{}]\nno end',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on invalid JSON', () {
      expect(
        () => extractCheckJsonPayload(
          'DR_CHECK_JSON_BEGIN\nnot-json\nDR_CHECK_JSON_END',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('Fase 11a — entities-file validation', () {
    late Directory tmp;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('d_rocket_check_test_');
    });
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('accepts a valid entities file (contains `entityMetas`)', () {
      final f = File('${tmp.path}/entities.dart')..writeAsStringSync(
            'final List entityMetas = [];',
          );
      expect(validateEntitiesFile(f.path), isNull);
    });

    test('rejects a file that does not declare `entityMetas`', () {
      final f = File('${tmp.path}/bad.dart')
        ..writeAsStringSync('final other = 1;');
      final err = validateEntitiesFile(f.path);
      expect(err, isNotNull);
      expect(err, contains('entityMetas'));
    });

    test('rejects a missing file', () {
      final err = validateEntitiesFile('${tmp.path}/does_not_exist.dart');
      expect(err, isNotNull);
      expect(err, contains('does not exist'));
    });
  });

  group('Fase 11a — check exit code computation', () {
    test('exit 0 when no diffs', () {
      expect(exitCodeForDiffs(<Map<String, Object?>>[]), equals(0));
    });

    test('exit 0 when only safe diffs', () {
      final diffs = <Map<String, Object?>>[
        <String, Object?>{'severity': 'safe'},
        <String, Object?>{'severity': 'safe'},
      ];
      expect(exitCodeForDiffs(diffs), equals(0));
    });

    test('exit 1 when any unsafe diff', () {
      final diffs = <Map<String, Object?>>[
        <String, Object?>{'severity': 'safe'},
        <String, Object?>{'severity': 'unsafe'},
      ];
      expect(exitCodeForDiffs(diffs), equals(1));
    });

    test('exit 1 when only unsafe diffs', () {
      final diffs = <Map<String, Object?>>[
        <String, Object?>{'severity': 'unsafe'},
      ];
      expect(exitCodeForDiffs(diffs), equals(1));
    });
  });
}