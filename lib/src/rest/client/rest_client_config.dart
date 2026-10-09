import 'http_client.dart';

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
  });

  /// Optional transport. Defaults to the current `dRest.client`.
  final HttpClient? client;

  /// Wrappers ordered from outermost to innermost.
  final List<HttpClientWrapper> wrappers;

  /// Creates the configured pipeline around [fallback].
  HttpClient build(HttpClient fallback) {
    HttpClient current = client ?? fallback;
    for (int i = wrappers.length - 1; i >= 0; i--) {
      current = wrappers[i](current);
    }
    return current;
  }
}
