import 'dart:developer' as developer;

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';
import 'package:vm_service/utils.dart';

void main() {
  test(
    'publishes diagnostics and serves the snapshot through VM Service',
    () async {
      final info = await developer.Service.getInfo();
      final serviceUri = info.serverUri;
      if (serviceUri == null) {
        markTestSkipped(
            'VM Service is unavailable; run this test with --debug');
        return;
      }

      DrocketDevToolsBridge.register();
      final diagnostics = DrocketDiagnostics.instance;
      diagnostics.clear();
      diagnostics.configure(
        enabled: true,
        publishToVmService: true,
        includeSensitiveData: false,
      );

      final service = await vmServiceConnectUri(
        convertToWebSocketUrl(serviceProtocolUrl: serviceUri).toString(),
      );
      addTearDown(service.dispose);
      await service.streamListen(EventStreams.kExtension);

      final vm = await service.getVM();
      final isolateId = vm.isolates!.first.id!;
      final eventFuture = service.onExtensionEvent.firstWhere(
        (event) => event.extensionKind == 'd_rocket.diagnostic',
      );

      diagnostics.record(
        DiagnosticEvent(
          category: DiagnosticCategory.database,
          operation: 'vm.service.test',
          startedAt: DateTime.now().toUtc(),
          success: true,
        ),
      );

      final event = await eventFuture.timeout(const Duration(seconds: 5));
      expect(event.extensionKind, 'd_rocket.diagnostic');
      expect(event.extensionData?.data['operation'], 'vm.service.test');

      final response = await service.callServiceExtension(
        'ext.d_rocket.diagnostics.snapshot',
        isolateId: isolateId,
      );
      expect(response.json?['enabled'], isTrue);
      expect(response.json?['events'], isA<List<dynamic>>());
      expect((response.json?['events'] as List<dynamic>), isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}
