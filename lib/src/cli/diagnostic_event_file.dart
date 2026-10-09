import 'dart:convert';
import 'dart:io';

import '../diagnostics/diagnostic_category.dart';
import '../diagnostics/diagnostic_event.dart';

/// Appends CLI diagnostics as newline-delimited JSON.
class DiagnosticEventFile {
  DiagnosticEventFile(String path)
      : _file = File(path)..createSync(recursive: true);

  final File _file;
  int _sequence = 0;

  void record({
    required String operation,
    required DateTime startedAt,
    required Duration duration,
    required bool success,
    Object? error,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final event = DiagnosticEvent(
      id: '${startedAt.microsecondsSinceEpoch}-${_sequence++}',
      category: DiagnosticCategory.migration,
      operation: operation,
      startedAt: startedAt,
      finishedAt: startedAt.add(duration),
      duration: duration,
      success: success,
      error: error?.toString(),
      metadata: <String, Object?>{
        'source': 'd_rocket_cli',
        ...metadata,
      },
    );
    _file.writeAsStringSync(
      '${jsonEncode(event.toJson())}\n',
      mode: FileMode.append,
    );
  }
}
