import 'sync_state_store.dart';

/// Test / dev in-memory [SyncStateStore] backed
/// by a `Map<String, Object?>`. No I/O.
class InMemorySyncStateStore implements SyncStateStore {
  InMemorySyncStateStore({
    String? initialClientId,
    int initialWatermark = 0,
  }) {
    if (initialClientId != null) {
      _map[_kClientId] = initialClientId;
    }
    if (initialWatermark != 0) {
      _map[_kWatermark] = initialWatermark;
    }
  }

  static const String _kClientId = 'd_rocket.client_id';
  static const String _kWatermark = 'd_rocket.sync_watermark';

  final Map<String, Object?> _map = <String, Object?>{};

  @override
  Future<String?> getClientIdAsync() async => _map[_kClientId] as String?;

  @override
  Future<void> setClientIdAsync(String clientId) async {
    _map[_kClientId] = clientId;
  }

  @override
  Future<int> getWatermarkAsync() async => (_map[_kWatermark] as int?) ?? 0;

  @override
  Future<void> setWatermarkAsync(int watermark) async {
    _map[_kWatermark] = watermark;
  }

  @override
  Future<void> clearAsync() async {
    _map.clear();
  }
}
