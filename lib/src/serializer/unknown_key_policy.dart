/// Policy for handling unknown keys during
/// deserialisation.
enum UnknownKeyPolicy {
  /// Throws an error if unknown keys are present.
  strict,

  /// Ignores unknown keys silently.
  ignore,

  /// Captures unknown keys in an `extra` field.
  capture,
}
