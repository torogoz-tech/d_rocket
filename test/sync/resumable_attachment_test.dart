import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('tracks resumable attachment checkpoints', () {
    const ResumableAttachmentState state = ResumableAttachmentState(
      attachmentId: 'photo-1',
      totalBytes: 10,
    );
    final ResumableAttachmentState committed = state.commit(4);
    const ResumableAttachmentChunk chunk = ResumableAttachmentChunk(
      attachmentId: 'photo-1',
      offset: 4,
      totalBytes: 10,
      bytes: <int>[1, 2, 3],
      isFinal: false,
    );

    expect(committed.progress, 0.4);
    expect(chunk.endOffset, 7);
    expect(chunk.isContiguous, isTrue);
    expect(() => committed.commit(11), throwsArgumentError);
  });
}
