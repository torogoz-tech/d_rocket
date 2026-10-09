import 'diagnostic_category.dart';

/// Immutable, serializable record of one runtime diagnostic event.
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.category,
    required this.operation,
    required this.startedAt,
    this.duration,
    this.success,
    this.statusCode,
    this.error,
    this.metadata = const <String, Object?>{},
  });

  final DiagnosticCategory category;
  final String operation;
  final DateTime startedAt;
  final Duration? duration;
  final bool? success;
  final int? statusCode;
  final String? error;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() => <String, Object?>{
        'category': category.name,
        'operation': operation,
        'startedAt': startedAt.toIso8601String(),
        if (duration != null) 'durationMicros': duration!.inMicroseconds,
        if (success != null) 'success': success,
        if (statusCode != null) 'statusCode': statusCode,
        if (error != null) 'error': error,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
