// + (refactor): thrown when
// the server returns a non-2xx status. Wraps a
// [RestException] (typically [RestHttpException] or
// [NetworkException]) so the user can catch a
// sync-specific exception without having to know the
// underlying transport.

class RestSyncException implements Exception {
  RestSyncException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    final String c = cause == null ? '' : ' (caused by $cause)';
    return 'RestSyncException: $message$c';
  }
}
