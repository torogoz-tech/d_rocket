/// One immutable chunk in a resumable attachment transfer.
class ResumableAttachmentChunk {
  const ResumableAttachmentChunk({
    required this.attachmentId,
    required this.offset,
    required this.totalBytes,
    required this.bytes,
    required this.isFinal,
  });

  final String attachmentId;
  final int offset;
  final int totalBytes;
  final List<int> bytes;
  final bool isFinal;

  int get endOffset => offset + bytes.length;

  bool get isContiguous => offset >= 0 && endOffset <= totalBytes;
}
