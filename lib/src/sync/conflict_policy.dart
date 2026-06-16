/// A typed conflict-resolution policy used by the
/// sync layer when applying a remote upsert to a
/// row that already exists locally (concurrent edit).
library;

import 'conflict_resolver.dart';
///
/// `ConflictPolicy` is the preferred API over the
/// bare [ConflictResolver] typedef (which is still
/// supported for back-compat). The typed form
/// documents the four common cases as named
/// constants and provides a single point of
/// extensibility for custom merge logic via
/// [ConflictPolicy.custom].
///
/// All four built-in variants are exposed as
/// static fields on the sealed class so the
/// call site reads like a value:
///
/// ```dart
/// final sync = MySyncProvider(
///   conflictPolicy: ConflictPolicy.lww,        // server wins
///   // or
///   conflictPolicy: ConflictPolicy.clientWins,  // local wins
///   // or
///   conflictPolicy: ConflictPolicy.custom(
///     MergeStrategies.preferLocalColumns(['updated_by']),
///   ),
/// );
/// ```
///
/// `LwwConflictResolver.instance` and
/// `CustomConflictResolver.wrap(resolver)` are
/// retained as back-compat shims and return the
/// same [ConflictResolver] functions as before.
sealed class ConflictPolicy {
  const ConflictPolicy();

  /// Server wins on every collision (the default
  /// for d_rocket since v0.5). Synonym for
  /// [serverWins].
  static const ConflictPolicy lww = LwwConflictPolicy();

  /// Server wins on every collision. Synonym for
  /// [lww] — the two constants return the same
  /// instance; pick whichever name reads better at
  /// the call site.
  static const ConflictPolicy serverWins = LwwConflictPolicy();

  /// Local wins on every collision. Inverse of
  /// [lww] / [serverWins]: the merged row keeps
  /// every local value, and remote fills in only
  /// the columns the local row does not have.
  static const ConflictPolicy clientWins = ClientWinsConflictPolicy();

  /// User-provided merge callback. Use when the
  /// built-in policies do not fit. The
  /// [MergeStrategies] helpers
  /// (`preferLocalColumns`, `preferRemoteColumns`,
  /// `maxOf`) plug in here.
  factory ConflictPolicy.custom(ConflictResolver resolver) =
      CustomConflictPolicy;

  /// Resolves a conflict between a local row
  /// (already in the local DB) and a remote
  /// payload (just received from the server).
  /// Returns the merged row to apply.
  Map<String, Object?> resolve(
    Map<String, Object?> localRow,
    Map<String, Object?> remotePayload,
  );
}

/// Server-wins policy. The merged row takes every
/// remote value and falls back to the local value
/// for columns the remote did not include.
class LwwConflictPolicy extends ConflictPolicy {
  /// Creates a server-wins policy. The public
  /// [ConflictPolicy.lww] and
  /// [ConflictPolicy.serverWins] constants are the
  /// preferred way to obtain an instance.
  const LwwConflictPolicy();

  @override
  Map<String, Object?> resolve(
    Map<String, Object?> localRow,
    Map<String, Object?> remotePayload,
  ) =>
      <String, Object?>{...localRow, ...remotePayload};
}

/// Client-wins policy. The merged row takes every
/// local value and falls back to the remote value
/// for columns the local row does not have.
class ClientWinsConflictPolicy extends ConflictPolicy {
  /// Creates a client-wins policy. The public
  /// [ConflictPolicy.clientWins] constant is the
  /// preferred way to obtain an instance.
  const ClientWinsConflictPolicy();

  @override
  Map<String, Object?> resolve(
    Map<String, Object?> localRow,
    Map<String, Object?> remotePayload,
  ) =>
      <String, Object?>{...remotePayload, ...localRow};
}

/// User-provided merge policy. Wraps a
/// [ConflictResolver] callback so it can be passed
/// to anything expecting a [ConflictPolicy].
class CustomConflictPolicy extends ConflictPolicy {
  /// Creates a policy that delegates to [resolver].
  /// The preferred way to obtain an instance is
  /// [ConflictPolicy.custom].
  const CustomConflictPolicy(this.resolver);

  /// The wrapped user callback. Called once per
  /// conflict; the returned row is applied.
  final ConflictResolver resolver;

  @override
  Map<String, Object?> resolve(
    Map<String, Object?> localRow,
    Map<String, Object?> remotePayload,
  ) =>
      resolver(localRow, remotePayload);
}
