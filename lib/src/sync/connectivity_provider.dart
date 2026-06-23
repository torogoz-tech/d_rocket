/// 2.0.0 — bandwidth-aware sync.
///
/// The [ConnectivityProvider] is the abstraction
/// that tells the sync layer what kind of network
/// is available right now. The sync layer uses
/// this to decide:
///
/// * Whether to sync at all (no network → skip).
/// * Whether to use a smaller batch size (cellular
///   vs wifi).
/// * Whether to use a different transport (e.g.
///   WebSocket push on wifi, polling on cellular).
///
/// The default implementation
/// ([NoopConnectivityProvider]) assumes the
/// network is always available — useful for tests
/// and for desktop apps. For mobile, the user
/// plugs in their own implementation (e.g.
/// backed by `connectivity_plus`).
///
/// ## Example
///
/// ```dart
/// // Default: assume always-online.
/// ctx.connectivity = NoopConnectivityProvider();
///
/// // Or wire up a real one (mobile):
/// ctx.connectivity = ConnectivityPlusProvider(
///   connectivity: Connectivity(),
///   onUnmeteredOnly: () => true,  // sync only on wifi
/// );
///
/// // The trigger can be bandwidth-aware:
/// final trigger = PeriodicSyncTrigger(
///   interval: Duration(minutes: 5),
///   connectivity: ctx.connectivity,
/// );
/// ```
library;

import 'dart:async';

/// The type of network currently available.
///
/// `none` means no network at all (the sync
/// should be skipped). `wifi` and `cellular` are
/// the most common; `vpn` and `ethernet` are
/// less common but possible on desktop/server.
enum NetworkType {
  /// No network available. Sync should be skipped.
  none,

  /// WiFi (or other unmetered connection).
  wifi,

  /// Cellular (metered). Sync should be throttled.
  cellular,

  /// VPN. Treat as unmetered (the user paid for
  /// it).
  vpn,

  /// Wired Ethernet. Treat as unmetered.
  ethernet,

  /// Unknown / unsupported. Conservative: treat
  /// as metered (skip sync to avoid surprise
  /// bandwidth).
  unknown,
}

/// A snapshot of the current connectivity state.
///
/// `networkType` is the active network (or `none`
/// if disconnected). `isOnline` is `true` if the
/// device can reach the internet.
class ConnectivityState {
  /// Creates a [ConnectivityState].
  const ConnectivityState({
    required this.networkType,
    required this.isOnline,
  });

  /// Disconnected.
  static const ConnectivityState offline = ConnectivityState(
    networkType: NetworkType.none,
    isOnline: false,
  );

  /// Connected to WiFi (or other unmetered).
  static const ConnectivityState wifi = ConnectivityState(
    networkType: NetworkType.wifi,
    isOnline: true,
  );

  /// Connected to cellular (metered).
  static const ConnectivityState cellular = ConnectivityState(
    networkType: NetworkType.cellular,
    isOnline: true,
  );

  /// The active network.
  final NetworkType networkType;

  /// `true` if the device can reach the
  /// internet.
  final bool isOnline;

  /// `true` if the network is unmetered (wifi,
  /// ethernet, vpn). The sync layer can use this
  /// to decide whether to do large downloads.
  bool get isUnmetered =>
      networkType == NetworkType.wifi ||
      networkType == NetworkType.ethernet ||
      networkType == NetworkType.vpn;

  /// `true` if the network is metered (cellular,
  /// unknown). The sync layer can use this to
  /// decide to throttle.
  bool get isMetered =>
      networkType == NetworkType.cellular ||
      networkType == NetworkType.unknown;

  @override
  String toString() =>
      'ConnectivityState(${networkType.name}, isOnline=$isOnline)';
}

/// The interface for a connectivity provider.
///
/// Two methods:
/// * [current] — returns the current state
///   synchronously (or asynchronously if the
///   provider needs to do a lookup).
/// * [changes] — a broadcast stream of
///   [ConnectivityState] changes.
///
/// Implementations:
///
/// * [NoopConnectivityProvider] — always returns
///   [ConnectivityState.wifi]. Good for tests and
///   desktop apps.
/// * ConnectivityPlusProvider (in
///   `d_rocket_engine_mobile`, 2.1.0) — backed by
///   `package:connectivity_plus`.
abstract interface class ConnectivityProvider {
  /// The current connectivity state. May be
  /// `async` if the provider needs to do a
  /// lookup.
  Future<ConnectivityState> current();

  /// A broadcast stream of [ConnectivityState]
  /// changes. New subscribers should receive the
  /// current state as the first event (replay-1).
  Stream<ConnectivityState> get changes;

  /// Convenience: `true` if the device is
  /// currently online.
  Future<bool> get isOnline async {
    final ConnectivityState s = await current();
    return s.isOnline;
  }

  /// Convenience: `true` if the current network
  /// is unmetered.
  Future<bool> get isUnmetered async {
    final ConnectivityState s = await current();
    return s.isUnmetered;
  }
}

/// The default [ConnectivityProvider]. Always
/// returns [ConnectivityState.wifi]. Good for
/// tests and desktop/server apps.
class NoopConnectivityProvider implements ConnectivityProvider {
  /// Creates a [NoopConnectivityProvider]. The
  /// optional [state] lets tests simulate
  /// different networks (e.g.
  /// `NoopConnectivityProvider(offlineState)` to
  /// pretend there's no network).
  NoopConnectivityProvider({ConnectivityState state = ConnectivityState.wifi})
      : _state = state;

  ConnectivityState _state;
  final StreamController<ConnectivityState> _controller =
      StreamController<ConnectivityState>.broadcast(
    sync: true,
  );

  @override
  Future<ConnectivityState> current() async => _state;

  @override
  Stream<ConnectivityState> get changes {
    // Replay-1: new subscribers get the current
    // state first.
    late StreamController<ConnectivityState> wrapper;
    StreamSubscription<ConnectivityState>? sub;
    wrapper = StreamController<ConnectivityState>(
      onListen: () {
        wrapper.add(_state);
        sub = _controller.stream.listen(wrapper.add,
            onError: wrapper.addError, onDone: wrapper.close);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return wrapper.stream;
  }

  /// Test helper: change the state and notify
  /// subscribers. Only [NoopConnectivityProvider]
  /// exposes this — real providers get the
  /// changes from the OS.
  void setState(ConnectivityState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  Future<bool> get isOnline async => _state.isOnline;

  @override
  Future<bool> get isUnmetered async => _state.isUnmetered;

  /// Closes the underlying stream. Tests should
  /// call this in `tearDown`.
  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

/// A [ConnectivityProvider] that gates sync
/// based on a predicate. Used to express rules
/// like "sync only on wifi" or "sync on any
/// network, but skip when in airplane mode".
///
/// Example:
/// ```dart
/// // Only sync on wifi.
/// final gated = GatedConnectivityProvider(
///   inner: NoopConnectivityProvider(),
///   predicate: (s) => s.networkType == NetworkType.wifi,
/// );
/// ```
class GatedConnectivityProvider implements ConnectivityProvider {
  /// Creates a [GatedConnectivityProvider] that
  /// wraps [inner] and applies [predicate] to
  /// filter the state. The [predicate] returns
  /// `true` to **allow** sync, `false` to
  /// **deny** (the state is reported as
  /// [ConnectivityState.offline]).
  GatedConnectivityProvider({
    required this.inner,
    required this.predicate,
  });

  /// The inner provider.
  final ConnectivityProvider inner;

  /// The predicate. `true` to allow sync, `false`
  /// to deny.
  final bool Function(ConnectivityState) predicate;

  @override
  Future<ConnectivityState> current() async {
    final ConnectivityState s = await inner.current();
    return predicate(s) ? s : ConnectivityState.offline;
  }

  @override
  Stream<ConnectivityState> get changes async* {
    await for (final ConnectivityState s in inner.changes) {
      yield predicate(s) ? s : ConnectivityState.offline;
    }
  }

  @override
  Future<bool> get isOnline async => (await current()).isOnline;

  @override
  Future<bool> get isUnmetered async => (await current()).isUnmetered;
}
