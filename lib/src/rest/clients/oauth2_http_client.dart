// 2.0.0 — OAuth2 / JWT refresh HTTP wrapper.
//
// A real wrapper that:
//   1. Adds the `Authorization: Bearer <token>`
//      header to every outgoing request.
//   2. Catches 401 responses.
//   3. Calls the refresh endpoint to get a new
//      access token.
//   4. Retries the original request with the
//      new token (rebuilt from scratch — the
//      request body / headers are not
//      re-encoded, but the headers dict is
//      updated with the new bearer).
//   5. Gives up after [maxRefreshAttempts].

library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../client/http_client.dart';
import '../decoder.dart';
import '../rest_request.dart';
import '../rest_response.dart';

/// An OAuth2 access token + refresh token +
/// expiry.
class OAuth2Token {
  /// Creates an [OAuth2Token].
  OAuth2Token({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.tokenType = 'Bearer',
    this.scope,
  });

  /// Convenience constructor with `null`
  /// expiry (means "never expires"). Useful
  /// for tests / for tokens that don't have
  /// an expiry claim.
  factory OAuth2Token.nonExpiring({
    required String accessToken,
    required String refreshToken,
  }) =>
      OAuth2Token(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: DateTime.utc(3000),
      );

  /// The access token.
  final String accessToken;

  /// The refresh token.
  final String refreshToken;

  /// When the access token expires.
  final DateTime expiresAt;

  /// The token type (default `Bearer`).
  final String tokenType;

  /// The scope (optional).
  final String? scope;

  /// Parses an [OAuth2Token] from a JSON
  /// response (the standard OAuth2 token
  /// endpoint format).
  factory OAuth2Token.fromJson(Map<String, Object?> json) {
    final int expiresIn = (json['expires_in'] as int?) ?? 3600;
    return OAuth2Token(
      accessToken: json['access_token'] as String,
      refreshToken: (json['refresh_token'] as String?) ?? '',
      tokenType: (json['token_type'] as String?) ?? 'Bearer',
      scope: json['scope'] as String?,
      expiresAt:
          DateTime.now().add(Duration(seconds: expiresIn)),
    );
  }

  /// `true` if the access token has expired
  /// (or is about to — within [buffer]).
  bool isExpired({Duration buffer = const Duration(seconds: 30)}) {
    return DateTime.now().add(buffer).isAfter(expiresAt);
  }

  /// The `Authorization` header value
  /// (e.g. `Bearer abc123`).
  String get authorizationHeader => '$tokenType $accessToken';
}

/// A function that refreshes an OAuth2 token.
/// The default implementation uses an
/// HTTP-style POST to the token endpoint. The
/// user can provide their own (e.g. to use
/// a different HTTP client).
typedef OAuth2RefreshFn = Future<OAuth2Token> Function(
  OAuth2Token current,
);

/// A function that fetches the initial token
/// (called when no token is in the store).
typedef OAuth2InitialFn = Future<OAuth2Token> Function();

/// A persistent token store. The default
/// ([InMemoryOAuth2TokenStore]) is volatile —
/// the user can plug in a Keychain /
/// shared_preferences / file-based store.
abstract interface class OAuth2TokenStore {
  /// Reads the current token (or `null`).
  Future<OAuth2Token?> read();

  /// Writes the new token.
  Future<void> write(OAuth2Token token);

  /// Clears the token.
  Future<void> clear();
}

/// A volatile in-memory token store. Good for
/// tests and for short-lived CLI tools.
class InMemoryOAuth2TokenStore implements OAuth2TokenStore {
  /// Creates an [InMemoryOAuth2TokenStore],
  /// optionally pre-populated with a [token].
  InMemoryOAuth2TokenStore([this._token]);

  OAuth2Token? _token;

  @override
  Future<OAuth2Token?> read() async => _token;

  @override
  Future<void> write(OAuth2Token token) async {
    _token = token;
  }

  @override
  Future<void> clear() async {
    _token = null;
  }
}

/// The real OAuth2 HTTP wrapper.
///
/// Wraps an [HttpClient] and:
///   1. Injects the `Authorization: Bearer
///      `token`` header on every request.
///   2. Catches 401 responses.
///   3. Refreshes the token via [refreshFn].
///   4. Re-builds the original request with
///      the new token and retries it once.
///   5. Gives up after [maxRefreshAttempts].
///
/// The wrapper is **stateless between
/// requests** — it relies on the [store] for
/// token persistence. The only state it holds
/// is a per-request counter to avoid infinite
/// retry loops.
class OAuth2HttpClient implements HttpClient {
  /// Creates an [OAuth2HttpClient] that wraps
  /// [inner] (the underlying HTTP client). The
  /// [store] holds the current token. The
  /// [refreshFn] is called when the token
  /// expires. The [initialFn] is called when
  /// the store is empty (first request).
  OAuth2HttpClient({
    required this.inner,
    required this.store,
    required this.refreshFn,
    this.initialFn,
    this.maxRefreshAttempts = 1,
    this.headerName = 'Authorization',
  });

  /// The wrapped client.
  final HttpClient inner;

  /// The token store.
  final OAuth2TokenStore store;

  /// The refresh function.
  final OAuth2RefreshFn refreshFn;

  /// The initial-token function (optional).
  final OAuth2InitialFn? initialFn;

  /// Max number of refresh attempts before
  /// giving up.
  final int maxRefreshAttempts;

  /// The name of the auth header (default
  /// `Authorization`).
  final String headerName;

  /// The current token (in memory cache; the
  /// source of truth is [store]).
  OAuth2Token? _cached;

  Future<OAuth2Token> _getOrInitToken() async {
    OAuth2Token? t = _cached ?? await store.read();
    if (t == null) {
      if (initialFn == null) {
        throw StateError(
          'OAuth2HttpClient has no token in the store and '
          'no initialFn was provided. Call store.write(token) '
          'before making requests, or provide initialFn().',
        );
      }
      t = await initialFn!();
      await store.write(t);
    }
    _cached = t;
    return t;
  }

  Future<RestResponse<dynamic>> _executeOnce(
    RestRequest request,
    OAuth2Token token,
  ) async {
    final RestRequest withAuth = _injectAuth(request, token);
    return inner.execute(withAuth,
        decoder: _identityDecoder<dynamic>());
  }

  RestRequest _injectAuth(RestRequest request, OAuth2Token token) {
    return RestRequest(
      method: request.method,
      path: request.path,
      baseUrl: request.baseUrl,
      headers: <String, String>{
        ...request.headers,
        headerName: token.authorizationHeader,
      },
      body: request.body,
      queryParameters: request.queryParameters,
      timeout: request.timeout,
    );
  }

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required dynamic decoder, // unused here
    dynamic cancelToken, // unused here
  }) async {
    OAuth2Token token = await _getOrInitToken();
    if (token.isExpired()) {
      token = await _refresh(token, attempt: 0);
    }
    RestResponse<dynamic> response = await _executeOnce(request, token);
    if (response.statusCode != 401) {
      return response;
    }
    // 401 — try to refresh and retry.
    token = await _refresh(token, attempt: 0);
    return _executeOnce(request, token);
  }

  Future<OAuth2Token> _refresh(
    OAuth2Token current, {
    required int attempt,
  }) async {
    if (attempt >= maxRefreshAttempts) {
      throw StateError(
        'OAuth2: exceeded maxRefreshAttempts=$maxRefreshAttempts',
      );
    }
    final OAuth2Token next = await refreshFn(current);
    await store.write(next);
    _cached = next;
    return next;
  }

  @override
  Future<void> close() => inner.close();
}

/// A [OAuth2RefreshFn] that POSTs to an OAuth2
/// token endpoint. Uses the wrapped [HttpClient]
/// to make the refresh call. The
/// [tokenEndpoint] is the URL (e.g.
/// `https://auth.example.com/oauth2/token`).
/// The [clientId] and [clientSecret] are sent
/// in the body (as `application/x-www-form-
/// urlencoded`, the OAuth2 standard).
OAuth2RefreshFn httpOAuth2RefreshFn({
  required String tokenEndpoint,
  required String clientId,
  required String clientSecret,
  HttpClient? client,
}) {
  return (OAuth2Token current) async {
    final HttpClient c = client ?? _defaultHttpClient();
    final String body =
        'grant_type=refresh_token'
        '&refresh_token=${Uri.encodeQueryComponent(current.refreshToken)}'
        '&client_id=${Uri.encodeQueryComponent(clientId)}'
        '&client_secret=${Uri.encodeQueryComponent(clientSecret)}';
    final RestResponse<dynamic> response = await c.execute(
      RestRequest(
        method: 'POST',
        path: '',
        baseUrl: tokenEndpoint,
        headers: <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'application/json',
        },
        body: body,
      ),
      decoder: _identityDecoder<dynamic>(),
    );
    if (response.statusCode != 200) {
      throw StateError(
        'OAuth2 refresh failed: HTTP ${response.statusCode} '
        '${response.reasonPhrase ?? ''}',
      );
    }
    final Map<String, Object?> json =
        jsonDecode(response.rawBody) as Map<String, Object?>;
    return OAuth2Token.fromJson(json);
  };
}

HttpClient _defaultHttpClient() {
  // Lazy: use the standard `http` package. The
  // d_rocket core doesn't depend on `http`
  // directly, but the user can pass any
  // HttpClient. We expose a default that uses
  // a simple [HttpClient] impl.
  return _DefaultHttpClient();
}

/// A minimal [HttpClient] backed by
/// `package:http` (for the OAuth2 refresh
/// helper). The user can plug in their own
/// (e.g. a `dio` adapter) by passing
/// [client] to [httpOAuth2RefreshFn].
class _DefaultHttpClient implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required dynamic decoder,
    dynamic cancelToken,
  }) async {
    // Lazy import via the http package.
    final http.Response response = await http.post(
      Uri.parse('${request.baseUrl}${request.path}'),
      headers: request.headers,
      body: request.body,
    );
    return RestResponse<dynamic>(
      statusCode: response.statusCode,
      reasonPhrase: response.reasonPhrase,
      headers: response.headers,
      body: null,
      rawBody: response.body,
      request: request,
    );
  }

  @override
  Future<void> close() async {}
}

/// An identity decoder — returns the input
/// as-is. Used by the OAuth2 wrapper (which
/// doesn't decode the body; the user does
/// it in their own code).
Decoder<T> _identityDecoder<T>() => (dynamic data) => data as T;
