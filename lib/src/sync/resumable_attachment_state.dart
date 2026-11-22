/// Progress checkpoint for a resumable attachment upload or download.
class ResumableAttachmentState {
  const ResumableAttachmentState({
    required this.attachmentId,
    required this.totalBytes,
    this.committedBytes = 0,
  });

  final String attachmentId;
  final int totalBytes;
  final int committedBytes;

  double get progress => totalBytes == 0 ? 1 : committedBytes / totalBytes;

  ResumableAttachmentState commit(int bytes) {
    if (bytes < committedBytes || bytes > totalBytes) {
      throw ArgumentError.value(bytes, 'bytes', 'Outside attachment bounds.');
    }
    return ResumableAttachmentState(
      attachmentId: attachmentId,
      totalBytes: totalBytes,
      committedBytes: bytes,
    );
  }
}
