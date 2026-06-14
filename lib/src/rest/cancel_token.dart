//: lightweight, framework-free
// cancellation token. Modelled on `package:dio`'s
// `CancelToken` (just the bits that matter):
//
// * The user gets one from `CancelToken`.
// * When the user navigates away (e.g. a
// `StatefulWidget.dispose`), they call
// `token.cancel('user navigated away')`.
// * The pending [HttpClient.execute] call
// surfaces a [RequestCancelledException].
//
// Why not `dart:async`'s `Completer`? Because
// [RestRequest] is `const`-constructible (the
// codegen emits `const RestRequest(...)` calls),
// and `Completer` cannot be `const`. A
// `CancelToken` is also more semantic — it reads
// as "cancel this request" rather than "complete
// a future for no apparent reason".

/// A token that can be attached to a [RestRequest] to
/// allow the caller to cancel an in-flight HTTP
/// request.
///
/// (new): the first-class answer to
/// "user navigated away mid-request, the result is
/// useless now, stop the network call". Before 8.2
/// the only way to "cancel" was to ignore the
/// returned [Future] — but the underlying socket
/// stayed open, the response body was still read
/// (wasting CPU + memory + bandwidth), and the
/// server kept running whatever the request asked
/// for.
///
/// ## Usage
///
/// ```dart
/// final token = CancelToken;
/// unawaited(httpClient.execute(
/// request,
/// decoder: jsonDecoder,
/// cancelToken: token,
///));
/// // ...later, the user navigates away:
/// token.cancel('user navigated away');
/// ```
///
/// Throwing away the `Future` (the typical
/// "abandon this call" pattern) is no longer
/// enough. Always pass a [CancelToken] for any
/// long-running request the user might want to
/// abort.
class CancelToken {
  /// `true` after [cancel] has been called. Once
  /// `true`, the token cannot be reset.
  bool get isCancelled => _cancelled;

  /// The reason string passed to [cancel] (or
  /// `'cancelled'` if [cancel] was called without
  /// an argument). `null` until [cancel] is called.
  String? get reason => _reason;

  bool _cancelled = false;
  String? _reason;

  /// (hook): called once, the moment
  /// [cancel] is invoked. The [HttpPackageClient]
  /// wires this to abort the underlying
  /// `http.Request` so the socket is closed
  /// immediately. Library users typically do NOT
  /// set this directly.
  void Function(String reason)? _onCancel;

  /// Cancels any [HttpClient.execute] call that
  /// has this token attached. Idempotent (second
  /// call is a no-op). The [reason] is surfaced
  /// via [RequestCancelledException.reason].
  void cancel([String reason = 'cancelled']) {
    if (_cancelled) return;
    _cancelled = true;
    _reason = reason;
    _onCancel?.call(reason);
  }

  /// (internal): register the cancel
  /// callback. Called by [HttpPackageClient]
  /// immediately before [http.Client.send]. The
  /// callback receives the cancel reason and is
  /// expected to abort the in-flight socket.
  ///
  /// Library users do NOT need to call this — it's
  /// part of the HttpClient contract.
  void onCancel(void Function(String reason)? cb) {
    if (_cancelled) {
      // Cancel already fired; invoke the callback
      // synchronously so the client can react.
      cb?.call(_reason ?? 'cancelled');
      return;
    }
    _onCancel = cb;
  }
}

/// Thrown from [HttpClient.execute] when the
/// [CancelToken] the user attached to the
/// [RestRequest] is cancelled before the response
/// finishes streaming.
class RequestCancelledException implements Exception {
  /// The reason string from [CancelToken.cancel].
  final String reason;

  /// Creates a [RequestCancelledException].
  RequestCancelledException(this.reason);

  @override
  String toString() => 'RequestCancelledException: $reason';
}
