import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  final diagnostics = DrocketDiagnostics.instance;

  setUp(() {
    diagnostics.clear();
    diagnostics.configure(enabled: true, publishToVmService: false);
  });

  tearDown(() {
    diagnostics.clear();
    diagnostics.configure(enabled: false, publishToVmService: true);
  });

  test('records migration steps and destructive SQL metadata', () {
    final executed = <String>[];
    final runner = MigrationRunner(
      createExecutor: () => (String sql, [List<Object?>? binds]) {
        executed.add(sql);
      },
    );

    runner.run(<MigrationBase>[_TestMigration()]);

    final event = diagnostics.snapshot.singleWhere(
      (candidate) => candidate.category == DiagnosticCategory.migration,
    );
    expect(executed, isNotEmpty);
    expect(event.operation, 'apply');
    expect(event.metadata['id'], '001');
    expect(event.metadata['version'], 1);
    expect(event.metadata['versionTo'], 1);
    expect(event.metadata['steps'], 2);
    expect(event.metadata['destructive'], isTrue);
    expect(event.metadata['destructiveSteps'], 1);
  });
}

class _TestMigration extends MigrationBase {
  @override
  String get id => '001';

  @override
  String get name => 'Create and alter';

  @override
  void up(MigrationExecutor exec) {
    exec('CREATE TABLE events (id INTEGER)');
    exec('ALTER TABLE events ADD COLUMN note TEXT');
  }
}
