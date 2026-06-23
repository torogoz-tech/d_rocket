// SYNC.2 — ConnectivityProvider + bandwidth-aware sync tests

import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('ConnectivityState:', () {
    test('offline isOnline=false', () {
      expect(ConnectivityState.offline.isOnline, isFalse);
      expect(ConnectivityState.offline.isUnmetered, isFalse);
      expect(ConnectivityState.offline.isMetered, isFalse);
    });

    test('wifi isOnline=true, unmetered', () {
      expect(ConnectivityState.wifi.isOnline, isTrue);
      expect(ConnectivityState.wifi.isUnmetered, isTrue);
      expect(ConnectivityState.wifi.isMetered, isFalse);
    });

    test('cellular isOnline=true, metered', () {
      expect(ConnectivityState.cellular.isOnline, isTrue);
      expect(ConnectivityState.cellular.isUnmetered, isFalse);
      expect(ConnectivityState.cellular.isMetered, isTrue);
    });

    test('unknown is metered (conservative)', () {
      const ConnectivityState unknown = ConnectivityState(
        networkType: NetworkType.unknown,
        isOnline: true,
      );
      expect(unknown.isMetered, isTrue);
    });
  });

  group('NoopConnectivityProvider:', () {
    test('default state is wifi (online, unmetered)', () async {
      final NoopConnectivityProvider p = NoopConnectivityProvider();
      expect((await p.current()).networkType, NetworkType.wifi);
      expect(await p.isOnline, isTrue);
      expect(await p.isUnmetered, isTrue);
      await p.close();
    });

    test('custom state (e.g. offline)', () async {
      final NoopConnectivityProvider p = NoopConnectivityProvider(
        state: ConnectivityState.offline,
      );
      expect((await p.current()).networkType, NetworkType.none);
      expect(await p.isOnline, isFalse);
      await p.close();
    });

    test('emits state changes on the stream', () async {
      final NoopConnectivityProvider p = NoopConnectivityProvider();
      final List<NetworkType> seen = <NetworkType>[];
      final Completer<void> done = Completer<void>();
      final StreamSubscription<ConnectivityState> sub = p.changes.listen((s) {
        seen.add(s.networkType);
        if (s.networkType == NetworkType.cellular && !done.isCompleted) {
          done.complete();
        }
      });
      // Yield so the subscription is wired up.
      await Future<void>.delayed(Duration.zero);
      p.setState(ConnectivityState.cellular);
      await done.future.timeout(const Duration(seconds: 1));
      await sub.cancel();
      await p.close();
      // wifi (replay) + cellular (live)
      expect(seen, <NetworkType>[NetworkType.wifi, NetworkType.cellular]);
    });
  });

  group('GatedConnectivityProvider:', () {
    test('predicate returning true lets the inner state through', () async {
      final GatedConnectivityProvider g = GatedConnectivityProvider(
        inner: NoopConnectivityProvider(state: ConnectivityState.wifi),
        predicate: (s) => true, // always allow
      );
      expect((await g.current()).networkType, NetworkType.wifi);
    });

    test('predicate returning false reports offline', () async {
      final GatedConnectivityProvider g = GatedConnectivityProvider(
        inner: NoopConnectivityProvider(state: ConnectivityState.wifi),
        predicate: (s) => false, // always deny
      );
      expect((await g.current()).networkType, NetworkType.none);
      expect(await g.isOnline, isFalse);
    });

    test('only-wifi predicate', () async {
      final NoopConnectivityProvider inner = NoopConnectivityProvider(
        state: ConnectivityState.wifi,
      );
      final GatedConnectivityProvider g = GatedConnectivityProvider(
        inner: inner,
        predicate: (s) => s.networkType == NetworkType.wifi,
      );
      // While wifi, allowed.
      expect((await g.current()).networkType, NetworkType.wifi);
      // Switch to cellular → denied.
      inner.setState(ConnectivityState.cellular);
      // The gating happens in the stream; the
      // .current() is async. We don't await
      // here; we just check the stream.
      // For .current(), the inner state is
      // already cellular, so the predicate
      // returns false → offline.
      expect((await g.current()).networkType, NetworkType.none);
    });
  });

  group('DbContext + connectivity:', () {
    test('default context has NoopConnectivityProvider', () {
      final _StubCtx ctx = _StubCtx();
      expect(ctx.connectivity, isA<NoopConnectivityProvider>());
    });

    test('autoSkipOnOffline defaults to true', () {
      final _StubCtx ctx = _StubCtx();
      expect(ctx.autoSkipOnOffline, isTrue);
    });

    test('user can swap the connectivity provider', () {
      final _StubCtx ctx = _StubCtx();
      final NoopConnectivityProvider custom = NoopConnectivityProvider(
        state: ConnectivityState.cellular,
      );
      ctx.connectivity = custom;
      expect(ctx.connectivity, same(custom));
    });
  });
}

/// A minimal concrete subclass of [DbContext]
/// for the unit tests in this file (we don't
/// need a real DB — we just need a context to
/// access the new fields).
class _StubCtx extends DbContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
