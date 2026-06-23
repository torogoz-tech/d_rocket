/// 2.0.0 — multi-tenant sync isolation.
///
/// A [TenantId] is a string that identifies
/// the tenant. Each tenant has its own
/// sync state (watermark, queue, etc.). The
/// same [SyncProvider] can serve multiple
/// tenants; the [MultiTenantSyncProvider]
/// wraps it and routes requests by tenant.
library;

/// A tenant identifier.
class TenantId {
  /// Creates a [TenantId] from a string.
  const TenantId(this.value);

  /// The string value (e.g. `'acme-corp'`).
  final String value;

  @override
  bool operator ==(Object other) =>
      other is TenantId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'TenantId($value)';
}

/// A map of `TenantId -> value`. The
/// [MultiTenantSyncStateStore] wraps a
/// single-tenant [SyncStateStore] and
/// dispatches by tenant.
class MultiTenantSyncStateStore<S> {
  /// Creates a [MultiTenantSyncStateStore]
  /// that uses [factory] to create a new
  /// [S] for each tenant.
  MultiTenantSyncStateStore(S Function(TenantId) factory) : _factory = factory;

  final S Function(TenantId) _factory;
  final Map<TenantId, S> _stores = <TenantId, S>{};

  /// The store for [tenant], creating it if
  /// it doesn't exist yet.
  S storeFor(TenantId tenant) {
    return _stores.putIfAbsent(tenant, () => _factory(tenant));
  }

  /// The number of tenants currently
  /// tracked.
  int get tenantCount => _stores.length;
}
