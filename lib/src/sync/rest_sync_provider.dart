// + (refactor):
// `RestSyncProvider` is an HTTP + JSON
// implementation of [SyncProvider]. POSTs the
// [SyncEnvelope] to `$baseUrl/sync`; GETs the
// watermark from `$baseUrl/sync/watermark`.
//
// architectural change: the provider
// now depends on the high-level [HttpClient]
// interface (layer 2 of `d_rocket`) instead of
// `package:http` directly. This brings two wins:
//
// 1. The provider automatically inherits every
// feature the [HttpClient] pipeline offers
// (interceptors, retry policies, circuit
// breaker, etc.) when the user supplies a
// composed client (e.g.
// `RetryingHttpClient(inner: HttpPackageClient)`).
// 2. Tests can mock the provider with a trivial
// `HttpClient` subclass — no more binding a
// local `HttpServer` if the user prefers a
// pure-mock test (the original `HttpServer`
// test in `rest_sync_test.dart` still works
// as-is because the default `HttpPackageClient`
// speaks real HTTP).

import 'dart:async';
import 'dart:convert';

import '../rest/client/http_client.dart';
import '../rest/client/http_package_client.dart';
import '../rest/cancel_token.dart';
import '../rest/decoder.dart';
import '../rest/error.dart';
import '../rest/rest_request.dart';
import '../rest/rest_response.dart';
import 'rest_sync_exception.dart';
import 'sync_envelope.dart';
import 'sync_provider.dart';

export 'rest_sync_exception.dart';
export '../rest/client/http_package_client.dart' show HttpPackageClient;

/// +: an HTTP + JSON
/// [SyncProvider] backed by the high-level
/// [HttpClient] interface.
///
/// * `POST $baseUrl/sync` with the JSON-encoded
/// envelope as the body. The response body
/// should be a JSON-encoded [SyncEnvelope].
/// * `GET $baseUrl/sync/watermark`. The response
/// body should be a plain int (as a String).
///
/// Both methods set `Content-Type: application/json`
/// on the request.
class RestSyncProvider implements SyncProvider {
  /// Creates a REST-backed sync provider.
  ///
  /// [baseUrl] is the API root (e.g.
  /// `https://api.example.com`). The provider
  /// appends `/sync` and `/sync/watermark` for
  /// the two endpoints.
  ///
  /// [client] is the [HttpClient] to use. If null,
  /// a default [HttpPackageClient] is created
  /// (which speaks real HTTP via `package:http`).
  /// For tests, pass a `MockClient` (via
  /// `HttpPackageClient(client: MockClient(...))`),
  /// or any custom `HttpClient` subclass.
  ///
  /// [headers] are extra HTTP headers (e.g. for
  /// auth: `'Authorization': 'Bearer $token'`).
  ///
  /// [timeout] is an optional per-call timeout.
  RestSyncProvider({
    required this.baseUrl,
    HttpClient? client,
    Map<String, String>? headers,
    Duration? timeout,
  })  : _client = client ?? HttpPackageClient(),
        _timeout = timeout,
        _headers = <String, String>{
          'Content-Type': 'application/json',
          if (headers != null) ...headers,
        };

  /// The base URL (e.g. `https://api.example.com`).
  final String baseUrl;

  final HttpClient _client;
  final Map<String, String> _headers;
  final Duration? _timeout;

  /// Exposes the underlying [HttpClient] (useful
  /// for tests, observability, or for wrapping the
  /// provider itself in another `SyncProvider`).
  HttpClient get client => _client;

  @override
  Future<SyncEnvelope> syncAsync(SyncEnvelope envelope) async {
    final RestRequest request = RestRequest(
      method: 'POST',
      path: '/sync',
      baseUrl: baseUrl,
      headers: _headers,
      body: jsonEncode(envelope.toJson()),
      timeout: _timeout,
    );
    try {
      final RestResponse<dynamic> response = await _client.execute(
        request,
        decoder: _identityDecoder,
      );
      final Map<String, Object?> json = response.body! as Map<String, Object?>;
      return SyncEnvelope.fromJson(json);
    } on RequestCancelledException {
      rethrow;
    } on RestException catch (e) {
      throw RestSyncException(
        'POST $baseUrl/sync failed: ${e.message}',
        cause: e,
      );
    }
  }

  @override
  Future<int> currentWatermarkAsync() async {
    final RestRequest request = RestRequest(
      method: 'GET',
      path: '/sync/watermark',
      baseUrl: baseUrl,
      headers: _headers,
      timeout: _timeout,
    );
    try {
      final RestResponse<dynamic> response = await _client.execute(
        request,
        decoder: _identityDecoder,
      );
      return int.parse(response.rawBody.trim());
    } on RequestCancelledException {
      rethrow;
    } on RestException catch (e) {
      throw RestSyncException(
        'GET $baseUrl/sync/watermark failed: ${e.message}',
        cause: e,
      );
    }
  }

  /// +: closes the
  /// underlying HTTP client. Call from `dispose`.
  Future<void> close() => _client.close();
}

/// Identity decoder — the `HttpClient` interface
/// requires a [Decoder] argument, but in this
/// provider we want the body as-is (a `Map` or a
/// `String` for the watermark), and we apply the
/// type conversion manually.
dynamic _identityDecoder(dynamic data) => data;
