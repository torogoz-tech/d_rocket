//: sync layer — the
// `SyncProvider` interface, the data envelope
// shape, the in-memory test provider, the
// conflict-resolution strategies, the trigger
// interface + 3 reference implementations, and
// the retry policy + 2 reference implementations.
//
// The pattern: offline-first ↔ cloud.
//
// 1. The user mutates entities locally. Changes
// accumulate in the `ChangeTracker` + the local
// DB.
// 2. When the device is online, the user calls
// `ctx.syncAsync(syncProvider)`.
// 3. `syncAsync` orchestrates a 3-step round-trip:
// a. Push: collect local changes, send to
// the provider.
// b. Pull: ask the provider for remote
// changes since the last sync watermark.
// c. Apply: insert / update / delete the
// remote rows locally (with last-write-wins
// conflict resolution).
// 4. Update the local watermark.

export 'conflict_resolver.dart';
export 'custom_conflict_resolver.dart';
export 'exponential_backoff_retry_policy.dart';
export 'io_file_sync_state_store.dart'
    if (dart.library.js_interop) 'web_file_sync_state_store.dart';
export 'in_memory_sync_provider.dart';
export 'in_memory_sync_state_store.dart';
export 'lww_conflict_resolver.dart';
export 'manual_sync_trigger.dart';
export 'merge_strategies.dart';
export 'no_retry_policy.dart';
export 'periodic_sync_trigger.dart';
export 'rest_sync_exception.dart';
export 'rest_sync_provider.dart';
export 'retry_decision.dart';
export 'retry_policy.dart';
export 'signal_sync_trigger.dart';
export 'sync_change.dart';
export 'sync_change_type.dart';
export 'sync_envelope.dart';
export 'sync_provider.dart';
export 'sync_state_store.dart';
export 'sync_trigger.dart';
