//: tests for the sync triggers —
// automatic sync on timer / manual fire / mixed.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('Fase 5.16 — PeriodicSyncTrigger', () {
    test('fires periodically and syncs', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      final _TriggerContext ctx = _TriggerContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      // Use a 50ms interval.
      final PeriodicSyncTrigger trigger = PeriodicSyncTrigger(
        interval: const Duration(milliseconds: 50),
      );
      ctx.startSyncTriggers(
          provider: provider, triggers: <SyncTrigger>[trigger]);
      // Wait for at least 3 ticks.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      ctx.stopSyncTriggers();
      // We expect at least 2 syncs (initial + after
      // 1 tick) — being lenient on exact count.
      expect(provider.pushLog.length, greaterThanOrEqualTo(2));
    });

    test('stop() halts the trigger', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      final _TriggerContext ctx = _TriggerContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      final PeriodicSyncTrigger trigger = PeriodicSyncTrigger(
        interval: const Duration(milliseconds: 30),
      );
      ctx.startSyncTriggers(
          provider: provider, triggers: <SyncTrigger>[trigger]);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final int beforeStop = provider.pushLog.length;
      ctx.stopSyncTriggers();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final int afterStop = provider.pushLog.length;
      // No more pushes after stop.
      expect(afterStop, beforeStop);
    });
  });

  group('Fase 5.16 — SignalSyncTrigger (manual / pull-to-refresh)', () {
    test('fire() triggers exactly one sync', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      final _TriggerContext ctx = _TriggerContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      final SignalSyncTrigger trigger = SignalSyncTrigger();
      ctx.startSyncTriggers(
          provider: provider, triggers: <SyncTrigger>[trigger]);
      // No sync yet.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.pushLog, isEmpty);
      // Fire.
      trigger.fire();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // 1 sync.
      expect(provider.pushLog, hasLength(1));
      // Fire again.
      trigger.fire();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.pushLog, hasLength(2));
      ctx.stopSyncTriggers();
    });
  });

  group('Fase 5.16 — mixed triggers', () {
    test('periodic + signal both work in parallel', () async {
      final InMemorySyncProvider provider = InMemorySyncProvider();
      final _TriggerContext ctx = _TriggerContext();
      await ctx.bootstrapSync(InMemorySyncStateStore());
      final PeriodicSyncTrigger periodic = PeriodicSyncTrigger(
        interval: const Duration(milliseconds: 80),
      );
      final SignalSyncTrigger signal = SignalSyncTrigger();
      ctx.startSyncTriggers(
        provider: provider,
        triggers: <SyncTrigger>[periodic, signal],
      );
      // Fire the signal 2 times while the
      // periodic is running.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      signal.fire();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      signal.fire();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // The total should be at least 2 (signals) +
      // 1 (periodic) = 3.
      expect(provider.pushLog.length, greaterThanOrEqualTo(3));
      ctx.stopSyncTriggers();
    });
  });
}

class _TriggerContext extends DbContext {
  @override
  AsyncQueryProvider? get asyncProvider => null;
  @override
  DbSet<T> createDbSet<T>(EntityMeta Function() m) {
    throw UnsupportedError('Not used in this test');
  }
}
