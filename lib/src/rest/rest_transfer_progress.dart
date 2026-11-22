/// Progress snapshot for a REST upload or download.
class RestTransferProgress {
  const RestTransferProgress({
    this.sentBytes = 0,
    this.totalSentBytes,
    this.receivedBytes = 0,
    this.totalReceivedBytes,
  });

  final int sentBytes;
  final int? totalSentBytes;
  final int receivedBytes;
  final int? totalReceivedBytes;

  double? get uploadFraction => _fraction(sentBytes, totalSentBytes);
  double? get downloadFraction =>
      _fraction(receivedBytes, totalReceivedBytes);

  bool get isComplete =>
      (totalSentBytes == null || sentBytes >= totalSentBytes!) &&
      (totalReceivedBytes == null || receivedBytes >= totalReceivedBytes!);

  static double? _fraction(int current, int? total) {
    if (total == null || total <= 0) return null;
    return (current / total).clamp(0.0, 1.0);
  }
}
