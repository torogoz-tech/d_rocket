import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sync_state_store.dart';

/// Dart VM / server file-backed [SyncStateStore]
/// that persists the state to a JSON file. The
/// file is created lazily on the first write.
///
/// Format:
/// ```json
/// {
/// "clientId": "client-",
/// "watermark": 42
/// }
/// ```
class FileSyncStateStore implements SyncStateStore {
  /// Creates a file-backed [SyncStateStore]. The
  /// [path] is the full path to the JSON file
  /// (use `path_provider.getApplicationDocumentsDirectory`
  /// on Flutter, or just a path like
  /// `~/.myapp/sync_state.json` on the Dart VM).
  FileSyncStateStore(this.path);

  /// Full path to the JSON file.
  final String path;

  Future<File> _file() async => File(path);

  Future<Map<String, Object?>> _read() async {
    final File f = await _file();
    if (!await f.exists()) {
      return <String, Object?>{};
    }
    final String content = await f.readAsString();
    if (content.trim().isEmpty) {
      return <String, Object?>{};
    }
    return jsonDecode(content) as Map<String, Object?>;
  }

  Future<void> _write(Map<String, Object?> map) async {
    final File f = await _file();
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(map));
  }

  @override
  Future<String?> getClientIdAsync() async {
    final Map<String, Object?> map = await _read();
    return map['clientId'] as String?;
  }

  @override
  Future<void> setClientIdAsync(String clientId) async {
    final Map<String, Object?> map = await _read();
    map['clientId'] = clientId;
    await _write(map);
  }

  @override
  Future<int> getWatermarkAsync() async {
    final Map<String, Object?> map = await _read();
    return (map['watermark'] as int?) ?? 0;
  }

  @override
  Future<void> setWatermarkAsync(int watermark) async {
    final Map<String, Object?> map = await _read();
    map['watermark'] = watermark;
    await _write(map);
  }

  @override
  Future<void> clearAsync() async {
    final File f = await _file();
    if (await f.exists()) {
      await f.delete();
    }
  }
}
