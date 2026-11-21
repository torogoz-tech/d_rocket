import 'dart:convert';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

import '../support/diagnostic_policy_client.dart';

void main() {
  test('redacts sensitive headers and nested body fields', () async {
    final DrocketDiagnostics diagnostics = DrocketDiagnostics.instance;
    diagnostics.clear();
    diagnostics.configure(
      enabled: true,
      publishToVmService: false,
      includeSensitiveData: true,
      diagnosticPolicy: const DiagnosticPolicy(
        sensitiveBodyFields: <String>{'cardNumber', 'cvv'},
      ),
    );

    final RestRequest request = RestRequest(
      method: 'POST',
      path: '/cards',
      headers: const <String, String>{
        'DPoP': 'proof-secret',
        'x-correlation-id': 'trace-1',
      },
      body: jsonEncode(<String, Object?>{
        'cardNumber': '4111111111111111',
        'nested': <String, Object?>{
          'cvv': '123',
          'safe': 'visible',
        },
        'items': <Object?>[
          <String, Object?>{'cardNumber': '5555555555554444'},
        ],
      }),
    );

    await DiagnosticHttpClient(
      DiagnosticPolicyClient(),
    ).execute(request, decoder: (dynamic body) => body);

    final String diagnostic = jsonEncode(diagnostics.snapshot.single.toJson());
    expect(diagnostic, isNot(contains('proof-secret')));
    expect(diagnostic, isNot(contains('4111111111111111')));
    expect(diagnostic, isNot(contains('5555555555554444')));
    expect(diagnostic, contains('<redacted>'));
    expect(diagnostic, contains('trace-1'));

    diagnostics.clear();
    diagnostics.configure(
      enabled: false,
      diagnosticPolicy: const DiagnosticPolicy(),
    );
  });
}
