/// An HTTP failure returned while opening an SSE connection.
class SseHttpException extends StateError {
  SseHttpException(this.statusCode, [this.detailMessage])
      : super('SSE connect failed: HTTP $statusCode');

  final int statusCode;
  final String? detailMessage;

  @override
  String toString() => detailMessage == null
      ? 'SseHttpException: HTTP $statusCode'
      : 'SseHttpException: HTTP $statusCode: $detailMessage';
}
