/// Identifies the supported UUID version policies.
enum UuidVersion {
  /// Identifies time-based UUIDs.
  v1,

  /// Identifies DCE Security UUIDs.
  v2,

  /// Identifies name-based UUIDs using MD5.
  v3,

  /// Identifies randomly generated UUIDs.
  v4,

  /// Identifies name-based UUIDs using SHA-1.
  v5,

  /// Identifies reordered time-based UUIDs.
  v6,

  /// Identifies Unix timestamp-based UUIDs.
  v7,

  /// Identifies application-defined UUIDs.
  v8,
}
