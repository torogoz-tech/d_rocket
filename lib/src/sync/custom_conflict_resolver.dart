import 'conflict_resolver.dart';

/// Wraps a user-provided [ConflictResolver]
/// callback so it can be set on
/// [EntityMeta.conflictResolver].
class CustomConflictResolver {
  static ConflictResolver wrap(ConflictResolver resolver) => resolver;
}
