# Layer 2 — REST

`@RestClient` marks an abstract class as a typed HTTP
client. The codegen (`d_rocket_builder`) reads the
annotation and emits a private implementation that
sends `package:http` requests through a pluggable
`HttpClient`. Resilience (retry, rate limit, circuit
breaker) is **composed** by wrapping the base client
with one of the three wrap-around clients
(`RetryingHttpClient`, `RateLimitedHttpClient`,
`CircuitBreakerHttpClient`). Cancellation is via
`CancelToken`.

This is the **transport layer**. Above it sits the
typed client code; below it sits `package:http` and
the platform's network stack.

---

## Table of contents

- [Basic usage](#basic-usage)
- [Verbs — `HttpGet`, `HttpPost`, ...](#verbs)
- [Parameter binding](#parameter-binding)
- [Composition of resilience — wrap-around clients](#composition-of-resilience)
- [Cancellation — `CancelToken`](#cancellation)
- [Interceptors — `RestInterceptor`](#interceptors)
- [Custom `HttpClient` implementations](#custom-httpclient)
- [Error model](#error-model)
- [Testing](#testing)
- [API reference](#api-reference)

---

## Basic usage

Define an abstract interface, annotate it. The codegen
emits the implementation:

```dart
@RestClient(baseUrl: 'https://api.example.com/v1')
abstract class ShopClient {
  @HttpGet('/products')
  Future<List<Product>> listProducts();

  @HttpGet('/products/{id}')
  Future<Product> getProduct(@Path('id') int id);

  @HttpPost('/orders')
  Future<Order> createOrder(@Body() OrderDraft draft);

  @HttpDelete('/orders/{id}')
  Future<void> cancelOrder(@Path('id') int id);
}
```

The generated implementation is a private class
(prefixed with `_`). The user calls the public
interface methods directly:

```dart
final products = await client.listProducts();
final product = await client.getProduct(42);
final order = await client.createOrder(OrderDraft(items: [...]));
await client.cancelOrder(order.id);
```

The `client` is provided by the codegen in
`d_rocket_registry.g.dart`. After `initializeD()`:

```dart
void main() {
  initializeD();
  final products = await ShopClient().listProducts();
}
```

To customise the transport (e.g. add retry), see
[Composition of resilience](#composition-of-resilience).

### Initialising the runtime

The runtime is a singleton accessible as `dRest`. The
default client is `HttpPackageClient` (over
`package:http`). To customise:

```dart
import 'package:d_rocket/d_rocket.dart';

void main() {
  // Use defaults (HttpPackageClient, no interceptors).
  dRest.useDefaults();
  // ... or:
  dRest.useDefaults(
    interceptors: [AuthInterceptor(loadToken)],
    defaultTimeout: Duration(seconds: 15),
  );
}
```

`dRest` exposes:

| Property / method | Purpose |
|---|---|
| `dRest.config` | The current `RestConfig`. |
| `dRest.client` | The current `HttpClient`. Read-only getter. |
| `dRest.client = someClient` | Replace the transport at runtime. |
| `dRest.useDefaults(...)` | Initialise with all defaults in one call. |
| `dRest.encodeBody<T>(value)` | Encode a value to JSON via the `Serializer`. |
| `dRest.decodeBody<T>(data)` | Decode a value via the `Serializer`. |

## Verbs

The codegen recognises the 7 standard HTTP verbs
(under the sealed class `HttpVerb`):

| Annotation | HTTP method | Default path |
|---|---|---|
| `@HttpGet([path])` | `GET` | `''` |
| `@HttpPost([path])` | `POST` | `''` |
| `@HttpPut([path])` | `PUT` | `''` |
| `@HttpPatch([path])` | `PATCH` | `''` |
| `@HttpDelete([path])` | `DELETE` | `''` |
| `@HttpHead([path])` | `HEAD` | `''` |
| `@HttpOptions([path])` | `OPTIONS` | `''` |

```dart
@HttpGet // -> GET https://api.example.com/v1/products
Future<List<Product>> listProducts();

@HttpGet('/{id}') // -> GET https://api.example.com/v1/products/{id}
Future<Product> getProduct(@Path('id') int id);
```

`HttpVerb` is a sealed class with two fields:

| Field | Type | Purpose |
|---|---|---|
| `path` | `String` | The relative path (with `{name}` placeholders for path params). Defaults to `''`. |
| `headers` | `Map<String, String>` | Extra headers for this method. Combined with the class-level `@RestClient.headers` and any `@Header` parameters. |

There is no `contentType` / `responseType` parameter
on the verb annotations. The default request body is
JSON, the default response body is JSON; raw byte
bodies are handled by `@RawBody` (out) and
`responseType: stream` (in, see below).

### Path placeholders

Use `{name}` tokens in the path. Bind by name via
`@Path('name')` (see [Parameter binding](#parameter-binding)).

## Parameter binding

The parameter annotations live in
`lib/src/rest/annotations/parameter.dart`. The base
sealed class is `Parameter`; concrete classes are
`Body`, `Query`, `Path`, `Header`, `Field`, `Part`,
`RawBody`.

| Annotation | Where it goes | Wire form |
|---|---|---|
| `@Body()` | Method parameter | Request body (JSON-encoded by the codegen) |
| `@Query([name])` | Method parameter | URL query string `?name=value` |
| `@Path([name])` | Method parameter | URL path placeholder `{name}` |
| `@Header([name])` | Method parameter | HTTP header `name: value` |
| `@Field([name])` | Method parameter | `application/x-www-form-urlencoded` field |
| `@Part([name])` | Method parameter | `multipart/form-data` part |
| `@RawBody()` | Method parameter | Raw `String` or `List<int>` body (no JSON serialisation) |

All parameter annotations take an optional positional
`name`. When `name` is `null`, the Dart parameter name
is used. Class-level headers (from `@RestClient.headers`
or `@Route.headers`) are combined with method-level
headers and parameter headers (parameter wins on
collision).

### `@Path` — URL path placeholders

```dart
@HttpGet('/products/{id}')
Future<Product> getProduct(@Path('id') int id);
```

The name in the annotation must match a `{name}` in
the verb's `path`. Path parameters are URL-encoded by
the codegen.

### `@Query` — query string

```dart
@HttpGet('/products')
Future<List<Product>> search(@Query('q') String? term);
```

If the `name` is omitted, the Dart parameter name is
used: `@Query() String? q`.

### `@Header` — HTTP header

```dart
@HttpGet('/profile')
Future<User> getProfile(@Header('Authorization') String token);
```

### `@Body` — request body

The default body type is JSON, encoded via the
`Serializer` registry from Layer 1. The codegen
calls `value.toJson()` on the parameter and sets the
request body.

```dart
@HttpPost('/orders')
Future<Order> createOrder(@Body() OrderDraft draft);
```

`OrderDraft` is a `@Serializable` class.

### `@Field` — form-urlencoded

```dart
@HttpPost('/login')
Future<Session> login(
  @Field('email') String email,
  @Field('password') String password,
);
```

The codegen sets `Content-Type:
application/x-www-form-urlencoded` automatically.

### `@Part` — multipart

```dart
@HttpPost('/upload')
Future<UploadResult> upload(
  @Part('file') MultipartFile file,
  @Part('description') String description,
);
```

`MultipartFile` is a wrapper holding a stream and a
filename. The codegen builds the multipart request
and streams the file.

### `@RawBody` — raw bytes

For endpoints that don't speak JSON (protobuf,
msgpack, etc.):

```dart
@HttpPost('/binary')
Future<void> sendBytes(@RawBody() List<int> bytes);
```

The codegen sends the body verbatim. The body must be
a `String` or `List<int>`; anything else throws
`RestConfigException` at request time.

## Composition of resilience

Resilience is **not** a `RestConfig` field. It is
provided by wrapping the base `HttpClient` with one
of three classes:

- `RetryingHttpClient` — retries failed requests
  using a `RetryPolicy`.
- `RateLimitedHttpClient` — token-bucket rate
  limiting.
- `CircuitBreakerHttpClient` — circuit breaker.

All three implement `HttpClient` themselves, so they
can be nested. The standard order is **innermost
first**:

```dart
final HttpClient base = HttpPackageClient();
final HttpClient withRetry = RetryingHttpClient(
  inner: base,
  policy: ExponentialBackoffRetryPolicy(
    maxAttempts: 4,
    baseDelay: Duration(milliseconds: 200),
    factor: 2.0,
  ),
);
final HttpClient withCb = CircuitBreakerHttpClient(
  inner: withRetry,
  failureThreshold: 5,
  openDuration: Duration(seconds: 30),
);
final HttpClient withRate = RateLimitedHttpClient(
  inner: withCb,
  tokensPerSecond: 20,
  burst: 10,
);
dRest.useDefaults(httpClient: withRate);
```

The wrap-around clients are compositional: the
outer client sees only the `HttpClient` contract, so
they can be swapped independently.

### `RetryingHttpClient`

```dart
class RetryingHttpClient implements HttpClient {
  RetryingHttpClient({
    required HttpClient inner,
    required RetryPolicy policy,
    bool Function(Object error)? shouldRetry,
  });
}
```

Wraps an `inner` client and retries failed requests
according to `policy`. On a retry-able failure, the
caller waits `decision.after` and re-sends. On
give-up, the last error is re-thrown.

`policy` is one of:

- `ExponentialBackoffRetryPolicy(maxAttempts, baseDelay, factor, maxDelay, jitter)`
  — the default. Exponential backoff with optional
  jitter.
- `NoRetryPolicy()` — never retries; useful for
  tests or for transient-error-free environments.
- A custom `RetryPolicy` implementation.

`shouldRetry` is an optional filter — if it returns
`false`, the request is NOT retried even if the
policy would say yes (e.g. don't retry 4xx errors
that are not 408/429).

### `RateLimitedHttpClient`

```dart
class RateLimitedHttpClient implements HttpClient {
  RateLimitedHttpClient({
    required HttpClient inner,
    required double tokensPerSecond,
    int burst = 1,
  });
}
```

Wraps an `inner` client and rate-limits requests
using a token bucket. The bucket has `burst` tokens;
each request consumes 1; tokens refill at
`tokensPerSecond`. If the bucket is empty, the
request blocks (async) until a token is available.

A `RateLimitedHttpClient.forTesting(...)` factory
exposes the initial state for deterministic tests.

### `CircuitBreakerHttpClient`

```dart
class CircuitBreakerHttpClient implements HttpClient {
  CircuitBreakerHttpClient({
    required HttpClient inner,
    int failureThreshold = 5,
    Duration openDuration = const Duration(seconds: 30),
    void Function(CircuitState state)? onStateChange,
  });
}
```

Wraps an `inner` client and applies a circuit
breaker. After `failureThreshold` consecutive
failures the circuit opens; subsequent requests
fail immediately with a `CircuitOpenException`
until `openDuration` elapses, then the circuit goes
half-open. The next request in half-open state
either closes the circuit (on success) or
re-opens it (on failure).

The state machine (`CircuitState` enum):

| State | Behavior |
|---|---|
| `CircuitState.closed` | Requests flow through normally. |
| `CircuitState.open` | Requests fail immediately with `CircuitOpenException`. |
| `CircuitState.halfOpen` | The next request is allowed through to test the waters. |

Inspect the current state with the public getter:

```dart
final cb = withCb as CircuitBreakerHttpClient;
print(cb.state);              // CircuitState.open
print(cb.consecutiveFailures);
```

`onStateChange` is a callback that fires on every
state transition — useful for metrics.

## Cancellation — `CancelToken`

`CancelToken` is the standard way to cancel an
in-flight request. The user gets one from
`CancelToken()`, calls `cancel('reason')` from
anywhere, and the pending `HttpClient.execute` call
aborts the socket and throws a
`RequestCancelledException`.

```dart
class _ShopPageState extends State<ShopPage> {
  final _cancel = CancelToken();

  @override
  void dispose() {
    _cancel.cancel('page disposed');
    super.dispose();
  }

  Future<void> _refresh() async {
    final products = await ShopClient().listProducts(
      cancelToken: _cancel,
    );
  }
}
```

`CancelToken` is modelled on `package:dio`'s
`CancelToken`. It is intentionally separate from
`dart:async`'s `Completer` because `RestRequest` is
`const`-constructible (the codegen emits
`const RestRequest(...)` calls) and `Completer`
cannot be `const`.

| Member | Purpose |
|---|---|
| `CancelToken()` | Creates a new token. |
| `token.isCancelled` | `true` after `cancel()` has been called. |
| `token.reason` | The reason string passed to `cancel`. |
| `token.cancel([reason])` | Cancels. Idempotent. |
| `token.onCancel(cb)` | (Internal) Register the cancel callback. Used by `HttpPackageClient` to abort the in-flight socket. |

Throwing away a `Future` (the typical
"abandon this call" pattern) is **not** enough —
the underlying socket stays open, the response body
is still read (wasting CPU + memory + bandwidth),
and the server keeps running whatever the request
asked for. Always pass a `CancelToken` for any
long-running request the user might want to abort.

## Interceptors — `RestInterceptor`

Interceptors sit between the call site and the
network. They are how you add cross-cutting concerns
(auth tokens, logging, tracing, metrics).

```dart
abstract class RestInterceptor {
  Future<RestRequest> onRequest(RestRequest request) async => request;
  Future<RestResponse<dynamic>> onResponse(RestResponse<dynamic> response) async => response;
  Future<RestException> onError(RestException error) async => error;
}

class AuthInterceptor implements RestInterceptor {
  @override
  Future<RestRequest> onRequest(RestRequest request) async {
    final token = await tokenStore.accessToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
    return request;
  }
}
```

The interceptor chain runs in registration order.
Each interceptor's `onRequest` is called with the
result of the previous. On the way back,
`onResponse` and `onError` are called in reverse
order.

Register globally via `RestConfig.interceptors`:

```dart
dRest.useDefaults(
  interceptors: [
    AuthInterceptor(loadToken),
    LoggingInterceptor(log: (line) => developer.log(line, name: 'rest')),
  ],
);
```

`LoggingInterceptor` is a boxed interceptor that
ships with d_rocket (since 1.1.0). It writes one
line per request, response, and error to a
caller-supplied sink. The default configuration
is conservative (method, URL, status — no headers,
no bodies). Headers and bodies are opt-in via
`includeHeaders: true` and `includeBodies: true`.
When bodies are included, the body text is passed
through `redactPragmaKey` by default, so a
SQLCipher database password attached to a request
body is never written to the log. To disable
redaction (e.g. when logging to a trusted local
sink), pass `redactBody: (s) => s`.

Or per-`HttpClient` (e.g. for a custom
implementation):

```dart
class MyClient implements HttpClient {
  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    final chain = CompositeInterceptor([AuthInterceptor(loadToken)]);
    final req = await chain.onRequest(request);
    // ... actually send the request ...
  }
}
```

## Custom `HttpClient` implementations

`HttpClient` is the only contract:

```dart
abstract class HttpClient {
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  });

  Future<void> close() async {}
}
```

The default implementation is `HttpPackageClient`
(over `package:http`). To use `package:dio` or any
other transport:

```dart
class DioRestClient implements HttpClient {
  final Dio _dio;
  DioRestClient(this._dio);

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    // Translate RestRequest -> dio.RequestOptions
    // send via _dio
    // translate response -> RestResponse
  }

  @override
  Future<void> close() async => _dio.close();
}

dRest.client = DioRestClient(Dio());
```

## Error model

The REST layer raises a typed exception hierarchy:

```dart
sealed class RestException implements Exception {
  final String message;
}

class RestHttpException extends RestException {
  final int statusCode;
  final String? reasonPhrase;
  final String rawBody;
  final Object? errorBody;
  final RestRequest request;

  /// For `application/problem+json` (RFC 7807) responses,
  /// returns the parsed problem document.
  Map<String, dynamic>? get problemDetails;
}

class NetworkException extends RestException {
  final Object? cause;
}

class RestConfigException extends RestException {}
```

| Exception | When |
|---|---|
| `RestHttpException` | Server returned a non-2xx status. Has `statusCode`, `rawBody`, `errorBody`. |
| `NetworkException` | Connection failed, DNS error, TLS error, timeout, etc. |
| `RestConfigException` | Misconfigured client (e.g. an `@RawBody` parameter received a non-`String`/non-`List<int>` value). |
| `CircuitOpenException` | (Not a `RestException`.) The `CircuitBreakerHttpClient` is open. |
| `RequestCancelledException` | (Not a `RestException`.) The `CancelToken` was cancelled mid-flight. |

Catch them with a single handler:

```dart
try {
  final product = await client.getProduct(id);
} on RestException catch (e) {
  if (e is RestHttpException && e.statusCode == 404) {
    // show "not found" UI
  } else {
    // generic error
  }
} on CircuitOpenException {
  // circuit was open
} on RequestCancelledException {
  // user cancelled
}
```

For richer error data, the response body is parsed as
JSON and attached to `RestHttpException.errorBody`.
For RFC 7807 (`application/problem+json`) responses,
use the `problemDetails` getter.

## Testing

`HttpClient` is an interface, so you can mock it
cleanly. The codegen-emitted `RestClient` accepts any
`HttpClient`, so you can substitute a `MockHttpClient`
in tests:

```dart
class MockHttpClient implements HttpClient {
  final List<RestRequest> seen = [];
  final Map<String, RestResponse Function(RestRequest)> routes;

  MockHttpClient(this.routes);

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    seen.add(request);
    final handler = routes[request.method + ' ' + request.path];
    if (handler == null) {
      throw StateError('No route registered for ${request.method} ${request.path}');
    }
    return handler(request);
  }

  @override
  Future<void> close() async {}
}

test('listProducts returns the products', () async {
  final mock = MockHttpClient({
    'GET /products': (_) => RestResponse(
      statusCode: 200,
      headers: {'content-type': 'application/json'},
      body: '[{"id": 1, "name": "Widget"}]',
      rawBody: '[{"id": 1, "name": "Widget"}]',
      request: ...,
    ),
  });
  dRest.client = mock;

  final products = await ShopClient().listProducts();
  expect(products, hasLength(1));
  expect(products.first.name, 'Widget');
  expect(mock.seen, hasLength(1));
});
```

For more complex mocking, `package:http`'s
`MockClient` is also compatible — wrap it in a small
adapter that implements `HttpClient`.

## LoggingInterceptor

A boxed `RestInterceptor` that emits one log line per
request, response, and error to a caller-supplied sink.
Headers and bodies are off by default, so the interceptor
is safe to drop in production without leaking auth tokens
or request payloads.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
dRest.useDefaults(
  interceptors: [
    LoggingInterceptor(
      log: (line) => developer.log(line, name: 'rest'),
    ),
  ],
);

// Verbose mode (bodies are redacted by default):
dRest.useDefaults(
  interceptors: [
    LoggingInterceptor(
      log: print,
      includeBodies: true,
    ),
  ],
);
```

Line shapes written by the interceptor:

- Request: `→ <method> <fullUrl>` (optional ` headers=...`, ` body=...`).
- Response: `← <statusCode> <method> <fullUrl>` (optional ` headers=...`, ` body=...`).
- Error: `× <runtimeType> <message>`. For `RestHttpException`, the trailing context is `( <statusCode> <method> <fullUrl> )` plus the optional body.

| Constructor parameter | Type | Default | Purpose |
|---|---|---|---|
| `log` | `void Function(String)` | required | Sink for each line. The interceptor does not append a trailing newline — the sink decides. |
| `includeHeaders` | `bool` | `false` | Append the request/response header map. Headers may contain auth tokens — enable with care. |
| `includeBodies` | `bool` | `false` | Append the request/response body, after redaction. |
| `redactBody` | `String Function(String)?` | `redactPragmaKey` | Scrubs a body string before logging. Pass `(s) => s` to disable. |

The default redactor (`redactPragmaKey`, added in 1.0.5)
replaces the value of any `PRAGMA key = '...'` or
`PRAGMA rekey = '...'` statement with `'***'`, so a
SQLCipher password embedded in a request body never
reaches the log. The interceptor does **not** measure
elapsed time — `RestRequest` is immutable, so a
stopwatch would have nowhere to live. Wrap the call site
in your own `Stopwatch` if you need per-call latency.

## HttpCache

In-memory ETag cache for HTTP responses. The
`cached_http_client.dart` file provides the cache
building block; the integration into the REST pipeline
is wired at the `DRest` level by a small wrapper that
the user attaches in front of any `HttpClient`. Entries
are keyed by `method + url`. On a hit the wrapper sends
`If-None-Match: <etag>` and returns the cached body when
the server replies `304 Not Modified`.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
final cache = HttpCache(
  maxEntries: 500,
  maxAge: const Duration(minutes: 10),
);

final key = cache.keyFor('GET', Uri.parse('https://api.example.com/v1/products'));
final existing = cache.get(key);
if (existing == null) {
  // miss — fetch from server, then store
  cache.put(key, CacheEntry(
    body: utf8.encode(responseBody),
    etag: responseEtag,
    fetchedAt: DateTime.now(),
  ));
} else {
  cache.recordRevalidation(); // server replied 304
}
```

| Class | Member | Purpose |
|---|---|---|
| `HttpCache` | `HttpCache({maxEntries = 1000, maxAge = 1h})` | Bounded in-memory cache. Thread-safe under Dart's single-isolate model. |
| `HttpCache` | `String keyFor(method, url)` | Canonical key for a request. |
| `HttpCache` | `CacheEntry? get(key)` | Returns the entry or `null`. Bumps `hits` / `misses`. An entry past `maxAge` counts as a miss. |
| `HttpCache` | `void put(key, entry)` | Stores. Evicts the entry with the oldest `fetchedAt` once `maxEntries` is exceeded. |
| `HttpCache` | `void recordRevalidation()` | Increments `revalidations` after a 304. |
| `HttpCache` | `clear()`, `hits`, `misses`, `revalidations`, `entryCount` | Maintenance and metrics. |
| `CacheEntry` | `body: List<int>`, `etag: String?`, `fetchedAt: DateTime` | One cached response. `body` is bytes so JSON and binary payloads share the same type. |

The cache holds **responses only**, not request bodies.
Eviction is by oldest `fetchedAt`. For multi-instance
deployments, plug a Redis-backed implementation in front
of the same wrapper.

## GzipCodec

Codec for gzip compression and decompression of
request/response bodies. The actual `dart:io` work is
split into `gzip_codec_io.dart` (VM) and
`gzip_codec_stub.dart` (browser) via conditional import;
`GzipCodec` is the static facade. On the browser, the
browser's fetch API transparently handles
`Content-Encoding: gzip`, so no client-side work is
needed in practice. If you want explicit compression on
the web, install a JS-interop polyfill via `setPolyfill`.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
final compressed = GzipCodec.encode(utf8.encode(jsonBody));
request.headers['Content-Encoding'] = 'gzip';
request.headers['Content-Type'] = 'application/json';
// ... send request, then on the way back:
final decompressed = utf8.decode(GzipCodec.decode(response.bodyBytes));
```

| Static member | Purpose |
|---|---|
| `GzipCodec.encode(List<int>)` | Compresses. On the VM this is `dart:io.gzip.encode`. |
| `GzipCodec.decode(List<int>)` | Decompresses. On the VM this is `dart:io.gzip.decode`. |
| `GzipCodec.isAvailable` | `true` on the VM, `true` on the browser if a polyfill was set, `false` otherwise. |
| `GzipCodec.setPolyfill({encode, decode})` | Browser hook. Wire to `CompressionStream` / `DecompressionStream`. Pass `null` for both to clear. |

`GzipUnavailableException` is thrown when neither
`dart:io` nor a polyfill is available. `CompressedBody`
(`body: List<int>`, `encoding: String` — default
`'gzip'`) is the marker class for already-compressed
payloads that the transport passes through verbatim.
There is no size threshold — every body is compressed.
If you want a size-based skip, gate on
`utf8.encode(body).length > N` before calling `encode`.

## HmacSha256Signer

Stateless HMAC signer for outbound requests. Backed by
`package:crypto`, which is already a transitive
dependency. The signer does not track counters or
nonces; for AWS-SigV4-style signing, compose this with
your own counter / nonce logic.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
final signer = HmacSha256Signer(utf8.encode('my-secret'));
final signature = signer.signRequest(
  method: 'GET',
  url: 'https://api.example.com/v1/orders',
  timestamp: '2026-06-22T10:00:00Z',
);
// Send `X-Signature: <signature>` as a header.
```

The canonical string passed through HMAC is:

```
<method>\n<url>\n<base64(body)>\n<timestamp>
```

| Member | Purpose |
|---|---|
| `HmacSha256Signer(secret, {algorithm = sha256})` | `secret` is the raw key bytes. `algorithm` selects SHA-1, SHA-256, or SHA-512. |
| `signBytes(message)` | Raw bytes out. |
| `signHex(message)` | Lowercase hex. |
| `signBase64(message)` | Base64. Used by `signRequest`. |
| `signRequest({method, url, body, timestamp})` | The canonical-string variant. Returns base64. |
| `verify(message, expected)` | Constant-time comparison against an expected signature. |
| `signatureLength` | `20` for SHA-1, `32` for SHA-256, `64` for SHA-512. |
| `HmacAlgorithm.{sha1, sha256, sha512}` | The three hash choices. SHA-256 is the default and the recommended one. |

`typedef HmacSha256 = HmacSha256Signer` is kept as a
backwards-compatible alias for code that imported the
original 2.0.0 stub name.

## OAuth2HttpClient

Wraps any `HttpClient` and adds bearer-token auth with
auto-refresh. On every request the wrapper injects
`Authorization: <tokenType> <accessToken>` (or your
custom `headerName`); on a 401 it calls `refreshFn`,
persists the new token to the store, and retries the
original request once. Token persistence is delegated
to an `OAuth2TokenStore` — `InMemoryOAuth2TokenStore`
is the volatile default.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
final store = InMemoryOAuth2TokenStore(initialToken);
final oauth = OAuth2HttpClient(
  inner: HttpPackageClient(),
  store: store,
  refreshFn: httpOAuth2RefreshFn(
    tokenEndpoint: 'https://auth.example.com/oauth2/token',
    clientId: 'my-app',
    clientSecret: 'shh',
  ),
  initialFn: () async {
    // First-run flow: client_credentials, code+pkce, etc.
    final res = await http.post(
      Uri.parse('https://auth.example.com/oauth2/token'),
      body: {'grant_type': 'client_credentials', 'client_id': 'my-app'},
    );
    return OAuth2Token.fromJson(jsonDecode(res.body));
  },
);
dRest.useDefaults(httpClient: oauth);
```

| Symbol | Purpose |
|---|---|
| `OAuth2Token({accessToken, refreshToken, expiresAt, tokenType, scope})` | A bearer + refresh pair. `fromJson` parses the standard OAuth2 token endpoint format. `isExpired({buffer = 30s})` returns `true` when the access token is at or past `expiresAt - buffer`. |
| `OAuth2TokenStore` | Abstract store interface: `read()`, `write(token)`, `clear()`. Plug a Keychain / `shared_preferences` / file-backed implementation for persistence. |
| `InMemoryOAuth2TokenStore([token])` | Volatile default. |
| `OAuth2HttpClient({inner, store, refreshFn, initialFn?, maxRefreshAttempts = 1, headerName = 'Authorization'})` | The wrapper. After `maxRefreshAttempts` failed refreshes it throws `StateError`. |
| `httpOAuth2RefreshFn({tokenEndpoint, clientId, clientSecret, client?})` | Ready-made `refresh_token` grant refresher. Posts `application/x-www-form-urlencoded` to the token endpoint and parses the response via `OAuth2Token.fromJson`. |

`execute` always rebuilds the request with the current
token (the headers dict is merged, the body is reused
verbatim). The wrapper does **not** decode the body —
the response is returned as `RestResponse<dynamic>` and
the user / codegen handles deserialization.

## RateLimitedHttpClient

Token-bucket rate limiter that wraps any `HttpClient`.
The bucket holds up to `burst` tokens, refills at
`tokensPerSecond`, and each request consumes one token.
When the bucket is empty the call `await`s until a token
becomes available — there is no maximum wait and no
queue priority.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
dRest.useDefaults(
  httpClient: RateLimitedHttpClient(
    inner: HttpPackageClient(),
    tokensPerSecond: 10,
    burst: 20,
  ),
);
```

| Constructor parameter | Type | Default | Purpose |
|---|---|---|---|
| `inner` | `HttpClient` | required | The wrapped transport. |
| `tokensPerSecond` | `double` | required | Sustained refill rate. |
| `burst` | `int` | `1` | Maximum bucket size — also the maximum number of requests that can fire back-to-back. |

`RateLimitedHttpClient.forTesting({inner, tokensPerSecond, burst, initialTokens})`
exposes the initial bucket state for deterministic
tests; use it from `setUp` to pre-fill the bucket.
`availableTokens` returns the current token count
(useful for asserts and dashboards). The refill timer
runs at 10 ms granularity while at least one waiter is
queued, and is cancelled when the queue drains. On
`close()` the timer is cancelled, every pending waiter
is completed (so they fall through to `inner.close()`),
and the inner client is closed. The constructor
initialises the bucket to `0` tokens — the first request
blocks until the first refill tick. If you need a warm
bucket, use the `forTesting` factory.

## RetryingHttpClient

Wraps any `HttpClient` and re-sends failed requests
according to a `RetryPolicy`. The default policy is
exponential backoff with jitter; `NoRetryPolicy()` is
provided for environments where transient errors never
fire (tests, local mock servers).

**Import:** `package:d_rocket/d_rocket.dart`

```dart
dRest.useDefaults(
  httpClient: RetryingHttpClient(
    inner: HttpPackageClient(),
    policy: ExponentialBackoffRetryPolicy(
      maxAttempts: 4,
      baseDelay: const Duration(milliseconds: 200),
      factor: 2.0,
    ),
    shouldRetry: (e) => e is NetworkException,
  ),
);
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `inner` | `HttpClient` | required | The wrapped transport. |
| `policy` | `RetryPolicy` | required | Decides retry vs give-up and the wait duration. |
| `shouldRetry` | `bool Function(Object)?` | `null` | Optional veto. Return `false` to skip the retry even when the policy says yes — e.g. to skip 4xx codes other than 408 / 429. |

Loop semantics: on `try`, success returns immediately;
on `catch`, the `shouldRetry` filter runs first, then
`policy.shouldRetry(attempt, error, stackTrace)` produces
a `RetryDecision`. `RetryDecision.retry(after)` waits
`after` and re-sends; `RetryDecision.giveUp()` rethrows
the last error verbatim. The body and headers of the
original `RestRequest` are reused on each retry — they
are not re-encoded. Cancellation is honoured via the
`cancelToken`: a cancelled request surfaces as
`RequestCancelledException` rather than triggering a
retry.

## CircuitBreakerHttpClient

Wraps any `HttpClient` and applies a three-state circuit
breaker. After `failureThreshold` consecutive failures
the circuit opens; subsequent requests fail immediately
with `CircuitOpenException` until `openDuration`
elapses, then the circuit goes half-open and the next
request is allowed through to test the waters.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
dRest.useDefaults(
  httpClient: CircuitBreakerHttpClient(
    inner: HttpPackageClient(),
    failureThreshold: 5,
    openDuration: const Duration(seconds: 30),
    onStateChange: (s) => metrics.gauge('rest.circuit', s.name),
  ),
);
```

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `inner` | `HttpClient` | required | The wrapped transport. |
| `failureThreshold` | `int` | `5` | Consecutive failures required to open the circuit. |
| `openDuration` | `Duration` | `30s` | How long the circuit stays open before transitioning to half-open. |
| `onStateChange` | `void Function(CircuitState)?` | `null` | Fires on every transition. Hook metrics here. |

`state` (one of `CircuitState.closed`, `CircuitState.open`,
`CircuitState.halfOpen`) and `consecutiveFailures` are
public getters — expose them to dashboards without
subclassing. State transitions:

- `closed` → `open` when `consecutiveFailures >= failureThreshold`.
- `open` → `halfOpen` when `DateTime.now() - openedAt >= openDuration` (the transition happens lazily on the next request, not via a timer).
- `halfOpen` → `closed` on the next success.
- `halfOpen` → `open` on the next failure (and the open window restarts).

`CircuitOpenException` (in `circuit_open_exception.dart`)
is **not** a `RestException` — it can fire without any
HTTP request being attempted, so the caller should
catch it alongside the `RestException` hierarchy:

```dart
try {
  final products = await client.listProducts();
} on RestException catch (e) {
  // 4xx / 5xx / network / config
} on CircuitOpenException {
  // back off; the circuit will recover on its own
}
```

## RequestCodec and Decoder

Low-level contracts that every `HttpClient`
implementation satisfies. They are typed aliases, not
classes — they exist so the runtime can pass a
`Decoder<dynamic>` alongside every request without
changing the `HttpClient` shape.

**Import:** `package:d_rocket/d_rocket.dart`

```dart
typedef Decoder<T> = T Function(dynamic data);

typedef RequestCodec = Future<RestResponse<dynamic>> Function(
  RestRequest request,
  Decoder<dynamic> decoder,
);
```

| Typedef | Shape | Purpose |
|---|---|---|
| `Decoder<T>` | `T Function(dynamic)` | Callback the codegen-emitted `RestClient` invokes to turn a raw response body into a typed value of `T`. The runtime does not ship one — it is generated per call site from the method's return type. |
| `RequestCodec` | `Future<RestResponse<dynamic>> Function(RestRequest, Decoder<dynamic>)` | Function signature a transport must satisfy when the runtime wants to invoke it with a per-call decoder (instead of holding the decoder in a field on the client). |

`RequestCodec` is exposed mainly so that custom
transports can compose with helpers like the
`CompositeInterceptor` and the OAuth2 wrapper without
re-implementing the `HttpClient` interface. Most user
code never imports the typedef — it shows up only when
writing a non-`http`-backed adapter (e.g. `Dio`-based)
that wants to be plug-compatible with the rest of the
runtime.

## API reference

### `@RestClient(baseUrl, headers, timeout)`

Interface annotation. Parameters:

| Parameter | Default | Purpose |
|---|---|---|
| `baseUrl` | `''` | Base URL. Combined with the per-method path. |
| `headers` | `{}` | Default headers on every method. |
| `timeout` | `null` | Default per-call timeout. |

### `@Route(path, baseUrl)`

Optional class-level annotation. Adds a path prefix
to every method and (optionally) overrides the
`baseUrl`:

```dart
@RestClient(baseUrl: 'https://api.x.com')
@Route('/api/v1/todos')
abstract class TodoClient {
  @HttpGet // -> GET https://api.x.com/api/v1/todos
  Future<List<Todo>> getAll;
}
```

| Parameter | Type | Purpose |
|---|---|---|
| `path` | `String` | Path prefix. |
| `baseUrl` | `String?` | Override the registry `baseUrl`. Useful when a specific client points at a different host. |

### `HttpVerb` and the 7 verb annotations

Sealed class `HttpVerb` with two fields:

| Field | Type | Purpose |
|---|---|---|
| `path` | `String` | Path with `{name}` placeholders. |
| `headers` | `Map<String, String>` | Method-level headers. |

Subclasses: `HttpGet`, `HttpPost`, `HttpPut`,
`HttpPatch`, `HttpDelete`, `HttpHead`, `HttpOptions`.

### `Parameter` and the 7 parameter annotations

Sealed class `Parameter` with one field:

| Field | Type | Purpose |
|---|---|---|
| `name` | `String?` | Wire name. Defaults to the Dart parameter name. |

Subclasses: `Body`, `Query`, `Path`, `Header`, `Field`,
`Part`, `RawBody`.

### `HttpClient`

Abstract transport interface. Methods:
`execute(request, decoder, cancelToken)`,
`close()`.

### `HttpPackageClient`

Default `HttpClient` implementation over
`package:http`. Constructor:
`HttpPackageClient({http.Client? client, interceptors = const []})`.

### `RestConfig`

Top-level config. Fields:

| Field | Type | Default | Purpose |
|---|---|---|---|
| `httpClient` | `HttpClient` | `HttpPackageClient()` | The transport. |
| `interceptors` | `List<RestInterceptor>` | `[]` | Cross-cutting concerns. |
| `defaultTimeout` | `Duration` | `30s` | Default per-call timeout. |
| `defaultHeaders` | `Map<String, String>` | `{}` | Default headers. |

### `DRest` / `dRest`

Singleton. Accessed via the top-level `dRest`
constant. Members: `config`, `client`, `client = ...`,
`useDefaults(...)`, `encodeBody<T>`, `decodeBody<T>`.

### `RestInterceptor` / `CompositeInterceptor`

Cross-cutting concern interface and the chain
implementation. Three methods: `onRequest`,
`onResponse`, `onError`.

### Wrap-around clients

| Class | Purpose | Constructor |
|---|---|---|
| `RetryingHttpClient` | Retries failed requests via a `RetryPolicy`. | `(inner, policy, shouldRetry?)` |
| `RateLimitedHttpClient` | Token-bucket rate limit. | `(inner, tokensPerSecond, burst: 1)` |
| `CircuitBreakerHttpClient` | Three-state circuit breaker. | `(inner, failureThreshold: 5, openDuration: 30s, onStateChange?)` |

### `CircuitState`

Enum with 3 values: `closed`, `open`, `halfOpen`.

### `CircuitOpenException`

Thrown by `CircuitBreakerHttpClient` when the circuit
is open. Not a `RestException` (it can fire without
an HTTP request even being attempted).

### `CancelToken` / `RequestCancelledException`

Cancellation. See [Cancellation](#cancellation).

### Retry policies (from the sync layer)

| Class | Purpose |
|---|---|
| `RetryPolicy` | Abstract base. |
| `ExponentialBackoffRetryPolicy` | Default. Exponential backoff with jitter. `(maxAttempts: 5, baseDelay: 1s, factor: 2, maxDelay: 30s, jitter: 100ms)` |
| `NoRetryPolicy` | Never retries. |
| `RetryDecision` | `RetryDecision.retry(after)` or `RetryDecision.giveUp()`. |

### Error hierarchy

| Class | When |
|---|---|
| `RestException` (sealed) | Base for HTTP / network / config errors. |
| `RestHttpException` | Non-2xx status. |
| `NetworkException` | Connection failure. |
| `RestConfigException` | Misconfiguration. |
| `CircuitOpenException` | Circuit breaker open. (Not a `RestException`.) |
| `RequestCancelledException` | Token cancelled. (Not a `RestException`.) |
