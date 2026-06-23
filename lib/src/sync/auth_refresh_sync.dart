/// 2.0.0 — auth-refresh-during-sync.
///
/// When a sync round-trip fails with HTTP 401
/// (Unauthorized), the auth token has
/// probably expired. The
/// [AuthRefreshHandler] is called to refresh
/// the token, and the sync is retried with the
/// new token.
///
/// ## Example
///
/// ```dart
/// final handler = AuthRefreshHandler(
///   onUnauthenticated: (e) async {
///     // Called when the server returns 401.
///     // Refresh the token and return the
///     // new one.
///     final newToken = await myAuthService.refresh();
///     return newToken;
///   },
///   maxRefreshAttempts: 2,
/// );
/// ```
library;

import 'dart:async';

/// A handler that refreshes the auth token
/// when a sync round-trip fails with 401.
class AuthRefreshHandler {
  /// Creates an [AuthRefreshHandler]. The
  /// [onUnauthenticated] callback is called
  /// when the server returns 401. It should
  /// refresh the token and return the new
  /// value. The handler is called up to
  /// [maxRefreshAttempts] times before giving
  /// up.
  AuthRefreshHandler({
    required this.onUnauthenticated,
    this.maxRefreshAttempts = 1,
  });

  /// The refresh callback. Returns the new
  /// auth token (the same format that was
  /// used in the original request — usually
  /// the value of the `Authorization` header,
  /// without the `Bearer ` prefix).
  final Future<String?> Function(Object error) onUnauthenticated;

  /// Maximum number of refresh attempts
  /// before giving up.
  final int maxRefreshAttempts;

  int _refreshAttempts = 0;
  String? _lastToken;

  /// `true` if the handler has been called at
  /// least once.
  bool get hasRefreshed => _refreshAttempts > 0;

  /// The number of refresh attempts so far.
  int get refreshAttempts => _refreshAttempts;

  /// The most recent token returned by
  /// [onUnauthenticated]. `null` if the
  /// handler hasn't been called yet.
  String? get lastToken => _lastToken;

  /// Tries to refresh the auth token. Returns
  /// the new token (or `null` if the refresh
  /// gave up after [maxRefreshAttempts]
  /// attempts).
  Future<String?> tryRefresh(Object error) async {
    if (_refreshAttempts >= maxRefreshAttempts) {
      return null;
    }
    _refreshAttempts++;
    final String? token = await onUnauthenticated(error);
    _lastToken = token;
    return token;
  }

  /// Resets the refresh counter. Call this
  /// after a successful sync, so the next 401
  /// starts a new refresh attempt budget.
  void reset() {
    _refreshAttempts = 0;
  }
}

/// A typedef for a function that checks if an
/// error is a 401 (Unauthorized) error.
typedef IsUnauthenticatedFn = bool Function(Object error);

/// The default 401 detector: checks if the
/// error is a `RestHttpException` with status
/// 401, or any object that has a `statusCode`
/// property equal to 401.
bool defaultIsUnauthenticated(Object error) {
  try {
    // Best-effort — we don't depend on the
    // REST layer here, so we just check the
    // type loosely.
    final dynamic dyn = error as dynamic;
    if (dyn.statusCode == 401) return true;
  } catch (_) {
    // Not a REST error.
  }
  return false;
}

/// Wraps a [Future] so that a 401 error
/// triggers an auth refresh and a retry.
Future<T> withAuthRefresh<T>({
  required Future<T> Function() operation,
  required AuthRefreshHandler handler,
  IsUnauthenticatedFn? isUnauthenticated,
}) async {
  final IsUnauthenticatedFn check = isUnauthenticated ?? defaultIsUnauthenticated;
  try {
    return await operation();
  } catch (e) {
    if (!check(e)) rethrow;
    final String? newToken = await handler.tryRefresh(e);
    if (newToken == null) rethrow;
    // Retry once with the new token. The
    // caller is responsible for using the new
    // token in the operation (e.g. by
    // re-reading the auth header from a
    // `late final` that's updated by the
    // handler).
    return await operation();
  }
}
