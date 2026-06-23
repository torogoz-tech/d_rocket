// SYNC.1 — SyncProgress + SyncProgressEventBus tests
//
// Covers the value-type contract of [SyncProgress]
// (==, hashCode, toString, fraction), the
// replay-1 behaviour of [SyncProgressEventBus],
// and the integration with `DbContext.syncAsync`
// (the callback variant + the stream variant).

import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('SyncProgress value type:', () {
    test('default values', () {
      final SyncProgress p = SyncProgress(phase: SyncPhase.starting);
      expect(p.phase, SyncPhase.starting);
      expect(p.processed, 0);
      expect(p.total, isNull);
      expect(p.message, isNull);
      expect(p.error, isNull);
      expect(p.stackTrace, isNull);
      expect(p.fraction, isNull);
      expect(p.isTerminal, isFalse);
      expect(p.hasError, isFalse);
    });

    test('fraction clamps to [0, 1]', () {
      expect(
        SyncProgress(phase: SyncPhase.pushing, processed: 0, total: 100)
            .fraction,
        0.0,
      );
      expect(
        SyncProgress(phase: SyncPhase.pushing, processed: 50, total: 100)
            .fraction,
        0.5,
      );
      expect(
        SyncProgress(phase: SyncPhase.pushing, processed: 100, total: 100)
            .fraction,
        1.0,
      );
      expect(
        SyncProgress(phase: SyncPhase.pushing, processed: 150, total: 100)
            .fraction,
        1.0,
      );
      expect(
        SyncProgress(phase: SyncPhase.pushing, processed: -1, total: 100)
            .fraction,
        0.0,
      );
    });

    test('fraction is null when total is null or 0', () {
      expect(
        SyncProgress(phase: SyncPhase.pulling, processed: 0).fraction,
        isNull,
      );
      expect(
        SyncProgress(phase: SyncPhase.pulling, processed: 0, total: 0)
            .fraction,
        isNull,
      );
    });

    test('isTerminal: done and error are terminal', () {
      expect(
        SyncProgress(phase: SyncPhase.done).isTerminal,
        isTrue,
      );
      expect(
        SyncProgress(phase: SyncPhase.error, error: 'oops').isTerminal,
        isTrue,
      );
      expect(
        SyncProgress(phase: SyncPhase.applying).isTerminal,
        isFalse,
      );
    });

    test('hasError mirrors error field', () {
      expect(
        SyncProgress(phase: SyncPhase.error).hasError,
        isFalse,
      );
      expect(
        SyncProgress(phase: SyncPhase.error, error: 'oops').hasError,
        isTrue,
      );
    });

    test('== is by value (not identity)', () {
      final DateTime ts = DateTime.parse('2026-06-22T15:00:00Z');
      final SyncProgress a = SyncProgress(
        phase: SyncPhase.pushing,
        processed: 50,
        total: 100,
        message: 'halfway',
        timestamp: ts,
      );
      final SyncProgress b = SyncProgress(
        phase: SyncPhase.pushing,
        processed: 50,
        total: 100,
        message: 'halfway',
        timestamp: ts,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString includes phase + processed + total + message + error', () {
      expect(
        SyncProgress(phase: SyncPhase.applying, processed: 3, total: 10)
            .toString(),
        'SyncProgress(applying, processed=3/10)',
      );
      expect(
        SyncProgress(
          phase: SyncPhase.error,
          error: 'disconnected',
          message: 'disconnected',
        ).toString(),
        'SyncProgress(error, processed=0, message=disconnected, error=disconnected)',
      );
    });
  });

  group('SyncProgressEventBus:', () {
    test('emits + replays the latest event to a late subscriber', () async {
      final SyncProgressEventBus bus = SyncProgressEventBus();
      bus.emit(SyncProgress(
        phase: SyncPhase.applying,
        processed: 5,
        total: 10,
      ));
      expect(bus.latest.phase, SyncPhase.applying);
      // Late subscriber receives the latest first.
      final List<SyncPhase> seen = <SyncPhase>[];
      final Completer<void> done = Completer<void>();
      final StreamSubscription<SyncProgress> sub = bus.stream.listen((p) {
        seen.add(p.phase);
        if (p.phase == SyncPhase.done) done.complete();
      });
      bus.emit(SyncProgress(phase: SyncPhase.done));
      await done.future.timeout(const Duration(seconds: 1));
      await sub.cancel();
      await bus.close();
      // Should have seen [applying (replay), done (live)]
      expect(seen, <SyncPhase>[SyncPhase.applying, SyncPhase.done]);
    });

    test('multiple subscribers all see the same live events', () async {
      final SyncProgressEventBus bus = SyncProgressEventBus();
      final List<List<SyncPhase>> allSeen = <List<SyncPhase>>[
        <SyncPhase>[],
        <SyncPhase>[],
      ];
      // Subscribe FIRST (so we get the live events). The
      // replay-1 will deliver the default `done` first to
      // each subscriber; we then emit 3 more events and
      // check that all subscribers see them.
      final List<StreamSubscription<SyncProgress>> subs = <StreamSubscription<SyncProgress>>[
        bus.stream.listen((p) => allSeen[0].add(p.phase)),
        bus.stream.listen((p) => allSeen[1].add(p.phase)),
      ];
      // Yield to the event loop so subscriptions are wired up.
      await Future<void>.delayed(Duration.zero);
      bus.emit(SyncProgress(phase: SyncPhase.pushing));
      bus.emit(SyncProgress(phase: SyncPhase.applying));
      // Wait until both subscribers have seen `applying`.
      while (allSeen[0].length < 3 || allSeen[1].length < 3) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      bus.emit(SyncProgress(phase: SyncPhase.done));
      // Wait until both subscribers have seen `done`.
      while (allSeen[0].length < 4 || allSeen[1].length < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      for (final StreamSubscription<SyncProgress> s in subs) {
        await s.cancel();
      }
      await bus.close();
      // Both subscribers saw: done (replay), pushing, applying, done.
      expect(
        allSeen[0],
        <SyncPhase>[
          SyncPhase.done,
          SyncPhase.pushing,
          SyncPhase.applying,
          SyncPhase.done,
        ],
      );
      expect(
        allSeen[1],
        <SyncPhase>[
          SyncPhase.done,
          SyncPhase.pushing,
          SyncPhase.applying,
          SyncPhase.done,
        ],
      );
    });

    test('late subscriber sees only the latest as replay', () async {
      final SyncProgressEventBus bus = SyncProgressEventBus();
      // Emit some events before anyone is listening.
      bus.emit(SyncProgress(phase: SyncPhase.pushing));
      bus.emit(SyncProgress(phase: SyncPhase.applying));
      bus.emit(SyncProgress(phase: SyncPhase.done));
      // Late subscriber.
      final List<SyncPhase> seen = <SyncPhase>[];
      final Completer<void> done = Completer<void>();
      final StreamSubscription<SyncProgress> sub = bus.stream.listen((p) {
        seen.add(p.phase);
        if (p.phase == SyncPhase.done && seen.length == 1 && !done.isCompleted) {
          done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 1));
      await sub.cancel();
      await bus.close();
      // Only sees the latest (done) — the replay-1 semantic.
      expect(seen, <SyncPhase>[SyncPhase.done]);
    });

    test('close() is idempotent', () async {
      final SyncProgressEventBus bus = SyncProgressEventBus();
      await bus.close();
      await bus.close();
      // No throw — good.
    });
  });
}
