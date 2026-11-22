import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('requires acknowledgement and applies backpressure', () async {
    final RealtimeDeliveryQueue<String> queue =
        RealtimeDeliveryQueue<String>(capacity: 1);
    final List<String> received = <String>[];
    final subscription = queue.deliveries.listen(
      (RealtimeDelivery<String> delivery) => received.add(delivery.payload),
    );

    queue.enqueue(const RealtimeDelivery<String>(id: '1', payload: 'event'));
    await Future<void>.delayed(Duration.zero);
    expect(queue.pendingCount, 1);
    expect(received, <String>['event']);
    expect(
      () => queue.enqueue(
        const RealtimeDelivery<String>(id: '2', payload: 'blocked'),
      ),
      throwsStateError,
    );
    expect(queue.ack('1'), isTrue);
    expect(queue.pendingCount, 0);
    expect(queue.ack('1'), isFalse);

    await subscription.cancel();
    await queue.close();
  });
}
