/// A boxed [RestInterceptor] that logs every request,
/// response, and error to a caller-supplied sink.
library;

import 'package:d_rocket/d_rocket.dart';
import 'package:d_rocket/src/sqlite/redact_pragma_key.dart';
///
/// The default configuration is conservative (method,
/// URL, status — no headers, no bodies) so it is safe
/// to drop in production without exposing secrets.
/// Headers and bodies are opt-in via the
/// [includeHeaders] and [includeBodies] flags.
///
/// When bodies are included, the body text is passed
/// through [redactBody] before being logged. The
/// default redactor is [redactPragmaKey] (added in
/// 1.0.5), which replaces the literal value of any
/// `PRAGMA key = '...'` or `PRAGMA rekey = '...'`
/// statement with `'***'`. This means a SQLCipher
/// database password attached to a request body
/// (e.g. inside a `RestRequest.body` that contains
/// a `PRAGMA key` line) is never written to the
/// log, even when body logging is enabled.
///
/// Pass `redactBody: (s) => s` (an identity function)
/// to disable redaction. The default is
/// `redactPragmaKey`, so most callers never need to
/// think about it.
///
/// ## Example
///
/// ```dart
/// dRest.use(LoggingInterceptor(
///   log: (line) => developer.log(line, name: 'rest'),
/// ));
///
/// // Verbose (with bodies, redacted by default):
/// dRest.use(LoggingInterceptor(
///   log: print,
///   includeBodies: true,
/// ));
///
/// // Custom redactor (e.g. for an OAuth bearer token):
/// dRest.use(LoggingInterceptor(
///   log: print,
///   includeBodies: true,
///   redactBody: (sql) => sql.replaceAll(
///     RegExp(r'''Bearer [A-Za-z0-9._-]+'''),
///     'Bearer ***',
///   ),
/// ));
/// ```
///
/// The interceptor does not measure elapsed time:
/// [RestRequest] is immutable, so a stopwatch would
/// have nowhere to live. If you need per-call latency,
/// wrap the call in your own `Stopwatch` before
/// invoking the codegen-emitted client method.
class LoggingInterceptor implements RestInterceptor {
  /// Creates an interceptor that writes one log line
  /// per request, response, and error to [log].
  ///
  /// [redactBody] defaults to [redactPragmaKey]; pass
  /// `null` to disable redaction.
  LoggingInterceptor({
    required this.log,
    this.includeBodies = false,
    this.includeHeaders = false,
    String Function(String)? redactBody,
  }) : redactBody = redactBody ?? redactPragmaKey;

  /// Where each line is written. The line is a single
  /// `String` with no trailing newline; the sink
  /// decides how to terminate it. Typical sinks:
  /// `print`, `developer.log`, or a custom
  /// `ZoneSpecification#print` handler.
  final void Function(String) log;

  /// Whether to append the request/response body to
  /// the log line. The body is passed through
  /// [redactBody] first. Default `false`.
  final bool includeBodies;

  /// Whether to append the request/response headers
  /// to the log line. Default `false`. Headers may
  /// contain auth tokens — enable with care.
  final bool includeHeaders;

  /// Function that scrubs a logged body string before
  /// it is written. Default: [redactPragmaKey].
  /// `null` disables redaction.
  final String Function(String)? redactBody;

  @override
  Future<RestRequest> onRequest(RestRequest request) async {
    final StringBuffer sb = StringBuffer()
      ..write('→ ')
      ..write(request.method)
      ..write(' ')
      ..write(request.fullUrl);
    if (includeHeaders) {
      sb
        ..write(' headers=')
        ..write(request.headers);
    }
    if (includeBodies) {
      sb
        ..write(' body=')
        ..write(_safeBody(request.bodyAsString));
    }
    log(sb.toString());
    return request;
  }

  @override
  Future<RestResponse<dynamic>> onResponse(
    RestResponse<dynamic> response,
  ) async {
    final StringBuffer sb = StringBuffer()
      ..write('← ')
      ..write(response.statusCode)
      ..write(' ')
      ..write(response.request.method)
      ..write(' ')
      ..write(response.request.fullUrl);
    if (includeHeaders) {
      sb
        ..write(' headers=')
        ..write(response.headers);
    }
    if (includeBodies) {
      sb
        ..write(' body=')
        ..write(_safeBody(response.rawBody));
    }
    log(sb.toString());
    return response;
  }

  @override
  Future<RestException> onError(RestException error) async {
    final StringBuffer sb = StringBuffer()
      ..write('× ')
      ..write(error.runtimeType)
      ..write(' ')
      ..write(error.message);
    if (error is RestHttpException) {
      sb
        ..write(' (')
        ..write(error.statusCode)
        ..write(' ')
        ..write(error.request.method)
        ..write(' ')
        ..write(error.request.fullUrl)
        ..write(')');
      if (includeBodies && error.rawBody.isNotEmpty) {
        sb
          ..write(' body=')
          ..write(_safeBody(error.rawBody));
      }
    }
    log(sb.toString());
    return error;
  }

  String _safeBody(String text) {
    if (text.isEmpty) return text;
    final String Function(String)? redactor = redactBody;
    if (redactor == null) return text;
    return redactor(text);
  }
}
