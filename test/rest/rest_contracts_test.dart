import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('RestPage preserves typed pagination metadata', () {
    const RestPage<String> page = RestPage<String>(
      items: <String>['a', 'b'],
      nextCursor: 'next',
      hasMore: true,
    );
    expect(page.items, <String>['a', 'b']);
    expect(page.nextCursor, 'next');
    expect(page.hasMore, isTrue);
  });

  test('RestTransferProgress reports upload and download fractions', () {
    const RestTransferProgress progress = RestTransferProgress(
      sentBytes: 25,
      totalSentBytes: 100,
      receivedBytes: 50,
      totalReceivedBytes: 100,
    );
    expect(progress.uploadFraction, 0.25);
    expect(progress.downloadFraction, 0.5);
    expect(progress.isComplete, isFalse);
  });
}
