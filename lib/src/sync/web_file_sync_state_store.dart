// Web stub for `FileSyncStateStore`.
//
// d_rocket targets the full Flutter matrix (iOS,
// Android, web, Windows, macOS, Linux) and the Dart
// VM. On native platforms the file-backed state
// store uses `dart:io` (see
// `io_file_sync_state_store.dart`). On the web
// `dart:io` is not available, so this stub is the
// conditional-import target. Every operation throws
// [UnsupportedError].
//
// To wire a real web transport, drop in
// `package:shared_preferences` (or `IndexedDB`,
// `localStorage`, etc.) and re-export a
// `SharedPreferencesSyncStateStore` adapter. The
// [SyncStateStore] contract is preserved so the call
// site does not need to change.

import 'sync_state_store.dart';

class FileSyncStateStore implements SyncStateStore {
  FileSyncStateStore();

  Never _unsupported() => throw UnsupportedError(
        'FileSyncStateStore is not available on the web. '
        'Use a `package:shared_preferences`-backed '
        '`SyncStateStore` adapter (see '
        '`lib/src/sync/web_file_sync_state_store.dart`).',
      );

  @override
  Future<String?> getClientIdAsync() async => _unsupported();

  @override
  Future<void> setClientIdAsync(String clientId) async => _unsupported();

  @override
  Future<int> getWatermarkAsync() async => _unsupported();

  @override
  Future<void> setWatermarkAsync(int watermark) async => _unsupported();

  @override
  Future<void> clearAsync() async => _unsupported();
}
