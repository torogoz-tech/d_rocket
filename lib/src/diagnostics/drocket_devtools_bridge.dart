import 'dart:convert';
import 'dart:developer' as developer;

import 'drocket_diagnostics.dart';

/// Registers the VM Service endpoints consumed by a DevTools extension.
class DrocketDevToolsBridge {
  DrocketDevToolsBridge._();

  static bool _registered = false;

  static void register() {
    if (_registered) return;
    _registered = true;
    DrocketDiagnostics.instance.configure(enabled: true);
    developer.registerExtension(
      'ext.d_rocket.diagnostics.snapshot',
      (String method, Map<String, String> parameters) async {
        final String payload = jsonEncode(<String, Object?>{
          'events': DrocketDiagnostics.instance.snapshot
              .map((event) => event.toJson())
              .toList(growable: false),
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
