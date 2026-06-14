import 'json_naming.dart';
import 'unknown_key_policy.dart';

/// Marks a class as serialisable by `d_rocket_builder`.
class Serializable {
  /// Optional alias used as discriminator fallback.
  final String? rename;

  /// Explicit discriminator value used for
  /// polymorphic payloads.
  final String? discriminator;

  /// JSON field name used to store/read the
  /// discriminator.
  final String? typeField;

  /// Policy for handling unknown keys during
  /// deserialisation. Default is
  /// [UnknownKeyPolicy.ignore] (backwards compatible
  /// with the original `strict: true` opt-in).
  final UnknownKeyPolicy unknownKeyPolicy;

  /// Global naming strategy for fields in this class.
  final JsonNaming naming;

  const Serializable({
    this.rename,
    this.discriminator,
    this.typeField,
    this.unknownKeyPolicy = UnknownKeyPolicy.ignore,
    this.naming = JsonNaming.none,
  });
}

const serializable = Serializable();
