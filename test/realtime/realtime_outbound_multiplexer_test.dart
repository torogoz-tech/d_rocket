import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  test('outbound queue retries with bounded attempts and acknowledges', () async {
    final RealtimeOutboundQueue<String> queue =
        RealtimeOutboundQueue<String>(maxAttempts: 2);
    final List<RealtimeOutboundMessage<String>> seen =
        <RealtimeOutboundMessage<String>>[];
    final subscription = queue.messages.listen(seen.add);

    queue.enqueue('hello', id: 'm1');
    expect(queue.retry('m1')?.attempt, 1);
    expect(queue.retry('m1'), isNull);
    expect(queue.pendingCount, 0);
    await Future<void>.delayed(Duration.zero);
    expect(seen.map((RealtimeOutboundMessage<String> item) => item.attempt),
        <int>[0, 1]);

    subscription.cancel();
    queue.close();
  });

  test('multiplexer isolates named channels', () async {
    final RealtimeMultiplexer<String> multiplexer = RealtimeMultiplexer<String>();
    final List<String> account = <String>[];
    final List<String> movement = <String>[];
    final accountSubscription = multiplexer.channel('account').listen(account.add);
    final movementSubscription =
        multiplexer.channel('movement').listen(movement.add);

    multiplexer.publish('account', 'updated');
    multiplexer.publish('movement', 'created');
    await Future<void>.delayed(Duration.zero);

    expect(account, <String>['updated']);
    expect(movement, <String>['created']);
    await accountSubscription.cancel();
    await movementSubscription.cancel();
    await multiplexer.close();
  });
}
