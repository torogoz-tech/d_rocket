import 'dart:convert';
import 'dart:developer' as developer;

import 'drocket_diagnostics.dart';

/// Registers the VM Service endpoints consumed by a DevTools extension.
class DrocketDevToolsBridge {
  DrocketDevToolsBridge._();

  static bool _registered = false;

  static void register({bool includeSensitiveData = false}) {
    if (_registered) return;
    _registered = true;
    DrocketDiagnostics.instance.configure(
      enabled: true,
      includeSensitiveData: includeSensitiveData,
    );
    developer.registerExtension(
      'ext.d_rocket.diagnostics.snapshot',
      (String method, Map<String, String> parameters) async {
        final String payload = jsonEncode(<String, Object?>{
          'events': DrocketDiagnostics.instance.snapshot
              .map((event) => event.toJson())
              .toList(growable: false),
          'buffer': <String, Object?>{
            'count': DrocketDiagnostics.instance.snapshot.length,
            'capacity': DrocketDiagnostics.instance.maxEvents,
          },
          'enabled': DrocketDiagnostics.instance.enabled,
          'includeSensitiveData':
              DrocketDiagnostics.instance.includeSensitiveData,
        });
        return developer.ServiceExtensionResponse.result(payload);
      },
    );
    developer.registerExtension(
      'ext.d_rocket.diagnostics.clear',
      (String method, Map<String, String> parameters) async {
        DrocketDiagnostics.instance.clear();
        return developer.ServiceExtensionResponse.result(
          jsonEncode(<String, Object?>{'cleared': true}),
        );
      },
    );
  }
}
