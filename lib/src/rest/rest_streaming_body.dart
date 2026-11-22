import 'dart:async';

import 'rest_transfer_progress.dart';

typedef RestTransferProgressCallback = void Function(
    RestTransferProgress progress);

/// A chunked request body for large REST uploads.
class RestStreamingBody {
  RestStreamingBody({
    required Stream<List<int>> chunks,
    this.totalBytes,
    this.contentType,
    this.onProgress,
  }) : chunks = _track(chunks, totalBytes, onProgress);

  final Stream<List<int>> chunks;
  final int? totalBytes;
  final String? contentType;
  final RestTransferProgressCallback? onProgress;

  static Stream<List<int>> _track(
    Stream<List<int>> source,
    int? totalBytes,
    RestTransferProgressCallback? onProgress,
  ) async* {
    int sent = 0;
    await for (final List<int> chunk in source) {
      sent += chunk.length;
      onProgress?.call(
        RestTransferProgress(sentBytes: sent, totalSentBytes: totalBytes),
      );
      yield chunk;
    }
  }
}
