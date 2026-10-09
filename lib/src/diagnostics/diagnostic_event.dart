import 'diagnostic_category.dart';

/// Immutable, serializable record of one runtime diagnostic event.
class DiagnosticEvent {
  const DiagnosticEvent({
    this.id,
    this.correlationId,
    required this.category,
    required this.operation,
    required this.startedAt,
    this.finishedAt,
    this.duration,
    this.success,
    this.statusCode,
    this.error,
    this.metadata = const <String, Object?>{},
  });

  final String? id;
  final String? correlationId;
  final DiagnosticCategory category;
  final String operation;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final Duration? duration;
  final bool? success;
  final int? statusCode;
  final String? error;
  final Map<String, Object?> metadata;

  DiagnosticEvent copyWith({String? id, DateTime? finishedAt}) {
    return DiagnosticEvent(
      id: id ?? this.id,
      correlationId: correlationId,
      category: category,
      operation: operation,
      startedAt: startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      duration: duration,
      success: success,
      statusCode: statusCode,
      error: error,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        if (id != null) 'id': id,
        if (correlationId != null) 'correlationId': correlationId,
        'category': category.name,
        'operation': operation,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (duration != null) 'durationMicros': duration!.inMicroseconds,
        if (success != null) 'success': success,
        if (statusCode != null) 'statusCode': statusCode,
        if (error != null) 'error': error,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };
}
