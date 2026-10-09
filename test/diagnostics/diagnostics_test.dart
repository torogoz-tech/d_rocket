import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  final DrocketDiagnostics diagnostics = DrocketDiagnostics.instance;

  setUp(() {
    diagnostics.clear();
    diagnostics.configure(enabled: true, maxEvents: 2);
  });

  tearDown(() {
    diagnostics.clear();
    diagnostics.configure(enabled: false, maxEvents: 500);
  });

  test('keeps a bounded snapshot and publishes structured events', () async {
    final Future<DiagnosticEvent> next = diagnostics.events.first;
    diagnostics.record(
      DiagnosticEvent(
        category: DiagnosticCategory.rest,
        operation: 'GET',
        startedAt: DateTime.utc(2026, 1, 1),
        success: true,
        metadata: const <String, Object?>{'url': '/events'},
      ),
    );

    expect(await next, isA<DiagnosticEvent>());
    expect(diagnostics.snapshot, hasLength(1));
    expect(diagnostics.snapshot.single.toJson()['category'], 'rest');
    expect(diagnostics.snapshot.single.id, isNotNull);
    expect(diagnostics.snapshot.single.finishedAt, isNotNull);
    expect(diagnostics.snapshot.single.toJson()['finishedAt'], isNotNull);
  });

  test('discards old events when the ring buffer reaches its limit', () {
    for (int i = 0; i < 3; i++) {
      diagnostics.record(
        DiagnosticEvent(
          category: DiagnosticCategory.database,
          operation: '$i',
          startedAt: DateTime.utc(2026, 1, 1),
        ),
      );
    }

    expect(diagnostics.snapshot.map((event) => event.operation),
        <String>['1', '2']);
  });

  test('does not retain events while disabled', () {
    diagnostics.configure(enabled: false);
    diagnostics.record(
      DiagnosticEvent(
        category: DiagnosticCategory.sync,
        operation: 'sync',
        startedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    expect(diagnostics.snapshot, isEmpty);
  });
}
