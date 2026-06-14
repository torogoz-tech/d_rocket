/// Naming policy applied to generated JSON keys.
enum JsonNaming {
  /// Keep field names as-is.
  none,

  /// Convert `camelCase`/`PascalCase` field names
  /// to `snake_case`. Example: `userProfile` →
  /// `user_profile`.
  snakeCase,

  /// Convert `snake_case`/`PascalCase` field names
  /// to `camelCase`. Example: `user_profile` →
  /// `userProfile`, `UserProfile` → `userProfile`
  /// (only the leading capital is lowered).
  camelCase,

  /// Convert `camelCase`/`snake_case` field names
  /// to `kebab-case`. Example: `userProfile` →
  /// `user-profile`.
  kebabCase,

  /// Convert field names to `PascalCase`
  /// (capitalize the first letter).
  /// Example: `userProfile` → `UserProfile`,
  /// `user_profile` → `UserProfile`.
  pascalCase,
}
