import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:d_rocket/d_rocket.dart';

/// Implementación por defecto de [HttpClient] basada en `package:http`.
class HttpPackageClient implements HttpClient {
  final http.Client _http;
  final List<RestInterceptor> interceptors;

  HttpPackageClient(
      {http.Client? client, this.interceptors = const <RestInterceptor>[]})
      : _http = client ?? http.Client();

  @override
  Future<RestResponse<dynamic>> execute(
    RestRequest request, {
    required Decoder<dynamic> decoder,
    CancelToken? cancelToken,
  }) async {
    final CompositeInterceptor chain = CompositeInterceptor(interceptors);
    final RestRequest req = await chain.onRequest(request);

    final Uri uri = Uri.parse(req.fullUrl);
    final http.Request httpReq = http.Request(req.method, uri);
    httpReq.headers.addAll(req.headers);

    if (req.body != null) {
      final Object body = req.body!;
      if (body is String) {
        httpReq.body = body;
      } else if (body is List<int>) {
        httpReq.bodyBytes = body;
      } else {
        // Refuse to silently fall back to `body.toString`: the
        // caller almost certainly meant a `String` or `List<int>` body
        // (the two types `package:http` accepts). Anything else is
        // either a misconfiguration or a forgotten `@RawBody` and we
        // want to surface that loudly.
        throw RestConfigException(
          'Unsupported body type for RestRequest: ${body.runtimeType}. '
          'Use String, List<int>, or annotate the parameter with '
          '`@RawBody()` to bypass serialisation.',
        );
      }
    }

    //: the caller can pass a [CancelToken]
    // via `request.cancelToken` (or the named
    // `cancelToken:` argument). If the token is
    // already cancelled when we enter, we abort
    // before even sending the request (saves a
    // round-trip + a doomed 200 from the server).
    final CancelToken? token = cancelToken ?? request.cancelToken;
    if (token?.isCancelled ?? false) {
      throw RequestCancelledException(token!.reason ?? 'cancelled');
    }
    final Completer<void> cancelCompleter = Completer<void>();
    token?.onCancel((String reason) {
      if (!cancelCompleter.isCompleted) {
        cancelCompleter.complete();
      }
    });

    try {
      final http.StreamedResponse streamed = await _http
          .send(httpReq)
          .timeout(req.timeout ?? const Duration(seconds: 30));

      //: race the body stream against the
      // cancel completer. If the user cancels
      // mid-stream, we stop reading the body
      // (freeing the socket) and throw.
      final Future<String> bodyFuture = streamed.stream.bytesToString();
      final Future<void> cancelFuture = cancelCompleter.future;
      // Listen to the body. If the cancel future
      // wins the race, we drop the subscription and
      // throw. The dropped subscription releases the
      // socket.
      final Future<String> firstToComplete = Future.any(<Future<String>>[
        bodyFuture,
        cancelFuture.then<String>((_) => throw RequestCancelledException(
              token?.reason ?? 'cancelled',
            )),
      ]);
      final String raw = await firstToComplete;

      final Map<String, String> responseHeaders = <String, String>{};
      streamed.headers.forEach((String name, String value) {
        responseHeaders[name] = value;
      });

      // Decodificación preliminar a JSON si el content-type lo indica.
      final dynamic decoded = _tryDecode(raw, responseHeaders);

      final RestResponse<dynamic> response = RestResponse<dynamic>(
        statusCode: streamed.statusCode,
        reasonPhrase: streamed.reasonPhrase,
        headers: responseHeaders,
        body: decoded,
        rawBody: raw,
        request: req,
      );

      if (response.isSuccess) {
        final RestResponse<dynamic> processed =
            await chain.onResponse(response);
        return processed;
      }

      final RestException error = RestHttpException(
        statusCode: streamed.statusCode,
        request: req,
        reasonPhrase: streamed.reasonPhrase,
        rawBody: raw,
        errorBody: decoded,
      );
      throw await chain.onError(error);
    } on TimeoutException catch (e) {
      throw NetworkException('Request timed out: ${req.fullUrl}', cause: e);
    } on http.ClientException catch (e) {
      //: when we abort the socket, package:http
      // raises a ClientException. Surface it as a
      // RequestCancelledException so the user can
      // `onError: (e) => e is RequestCancelledException`.
      if (token?.isCancelled ?? false) {
        throw RequestCancelledException(token?.reason ?? 'cancelled');
      }
      throw NetworkException('Network error: ${e.message}', cause: e);
    } on RestException {
      rethrow;
    } on RequestCancelledException {
      rethrow;
    } catch (e) {
      if (token?.isCancelled ?? false) {
        throw RequestCancelledException(token?.reason ?? 'cancelled');
      }
      throw NetworkException('Unexpected error: $e', cause: e);
    }
  }

  dynamic _tryDecode(String raw, Map<String, String> headers) {
    if (raw.isEmpty) return null;
    final String? contentType =
        headers['content-type'] ?? headers['Content-Type'];
    if (contentType == null) return raw;
    if (contentType.contains('application/json') ||
        contentType.contains('+json')) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return raw;
      }
    }
    return raw;
  }

  @override
  Future<void> close() async {
    _http.close();
  }
}
