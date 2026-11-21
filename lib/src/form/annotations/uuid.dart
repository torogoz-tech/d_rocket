import 'uuid_version.dart';

/// Validates a string as a canonical UUID.
class Uuid {
  /// Creates a UUID validation annotation.
  const Uuid({
    this.version,
    this.message,
    this.code = 'uuid.invalid',
  });

  /// The required UUID version, or `null` for any supported version.
  final UuidVersion? version;

  /// The optional message shown when validation fails.
  final String? message;

  /// The stable validation code used for localization and telemetry.
  final String code;
}
