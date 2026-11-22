import 'http_client.dart';
import 'diagnostic_http_client.dart';
import '../../diagnostics/drocket_diagnostics.dart';
import '../../transport/transport_policy.dart';
import '../../transport/transport_policy_http_client.dart';
import '../rest_query_cache.dart';

/// Builds the HTTP client used by one generated REST client.
typedef HttpClientWrapper = HttpClient Function(HttpClient inner);

/// Optional per-instance configuration for a generated `@RestClient`.
///
/// Wrappers are listed from outermost to innermost. The generated client
/// continues to use the global `dRest.client` when this configuration is not
/// supplied.
class RestClientConfig {
  /// Creates per-instance generated-client configuration.
  const RestClientConfig({
    this.client,
    this.wrappers = const <HttpClientWrapper>[],
    this.baseUrl,
    this.queryCache,
    this.transportPolicy,
    this.transportMaxAttempts = 1,
  });

  /// Optional transport. Defaults to the current `dRest.client`.
  final HttpClient? client;

  /// Wrappers ordered from outermost to innermost.
  final List<HttpClientWrapper> wrappers;

  /// Optional runtime base URL for this generated client instance.
  ///
  /// When omitted, the URL declared by `@RestClient` is used.
  final String? baseUrl;

  /// Optional cache owned by this generated client instance.
  ///
  /// When omitted, the generated client falls back to [dRest.queryCache] so
  /// existing applications keep their current behavior.
  final RestQueryCache? queryCache;

  /// Optional policy shared with SSE and streaming transports.
  final TransportPolicy? transportPolicy;

  /// Maximum attempts allowed when [transportPolicy] requests a repeat.
  final int transportMaxAttempts;

  /// Creates the configured pipeline around [fallback].
  HttpClient build(HttpClient fallback) {
    HttpClient current = client ?? fallback;
    for (int i = wrappers.length - 1; i >= 0; i--) {
      current = wrappers[i](current);
    }
    if (transportPolicy != null) {
      current = TransportPolicyHttpClient(
        inner: current,
        policy: transportPolicy!,
        maxAttempts: transportMaxAttempts,
      );
    }
    if (DrocketDiagnostics.instance.enabled &&
        current is! DiagnosticHttpClient) {
      current = DiagnosticHttpClient(current);
    }
    return current;
  }
}
