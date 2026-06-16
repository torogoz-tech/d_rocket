// Tests for the typed ConflictPolicy hierarchy.
//
// The contract being tested is the merge semantics
// of each built-in policy and the round-trip through
// the custom factory. The bare ConflictResolver
// typedef and the LwwConflictResolver /
// CustomConflictResolver shims are covered
// separately in test/sync/conflict_resolver_test.dart.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('ConflictPolicy — built-in constants', () {
    test('lww and serverWins are the same instance', () {
      expect(identical(ConflictPolicy.lww, ConflictPolicy.serverWins), isTrue);
    });

    test('lww and clientWins are different instances', () {
      expect(identical(ConflictPolicy.lww, ConflictPolicy.clientWins), isFalse);
    });

    test('lww is an LwwConflictPolicy', () {
      expect(ConflictPolicy.lww, isA<LwwConflictPolicy>());
    });

    test('clientWins is a ClientWinsConflictPolicy', () {
      expect(ConflictPolicy.clientWins, isA<ClientWinsConflictPolicy>());
    });
  });

  group('ConflictPolicy.lww (server-wins) — merge semantics', () {
    test('remote value wins on a column collision', () {
      final Map<String, Object?> merged = ConflictPolicy.lww.resolve(
        <String, Object?>{'a': 1, 'b': 2},
        <String, Object?>{'b': 99, 'c': 3},
      );
      expect(merged, <String, Object?>{'a': 1, 'b': 99, 'c': 3});
    });

    test('remote columns missing in the local row are added', () {
      final Map<String, Object?> merged = ConflictPolicy.lww.resolve(
        <String, Object?>{'a': 1},
        <String, Object?>{'b': 2},
      );
      expect(merged, <String, Object?>{'a': 1, 'b': 2});
    });

    test('local columns missing in the remote row are kept', () {
      final Map<String, Object?> merged = ConflictPolicy.lww.resolve(
        <String, Object?>{'a': 1, 'b': 2},
        <String, Object?>{'a': 99},
      );
      expect(merged, <String, Object?>{'a': 99, 'b': 2});
    });

    test('an empty remote payload keeps the local row verbatim', () {
      const Map<String, Object?> local = <String, Object?>{'a': 1, 'b': 2};
      final Map<String, Object?> merged =
          ConflictPolicy.lww.resolve(local, const <String, Object?>{});
      expect(merged, local);
    });
  });

  group('ConflictPolicy.clientWins — merge semantics', () {
    test('local value wins on a column collision', () {
      final Map<String, Object?> merged = ConflictPolicy.clientWins.resolve(
        <String, Object?>{'a': 1, 'b': 2},
        <String, Object?>{'b': 99, 'c': 3},
      );
      expect(merged, <String, Object?>{'a': 1, 'b': 2, 'c': 3});
    });

    test('remote columns missing in the local row are added', () {
      final Map<String, Object?> merged = ConflictPolicy.clientWins.resolve(
        <String, Object?>{'a': 1},
        <String, Object?>{'b': 2},
      );
      expect(merged, <String, Object?>{'a': 1, 'b': 2});
    });

    test('an empty local row keeps the remote row verbatim', () {
      const Map<String, Object?> remote = <String, Object?>{'a': 1, 'b': 2};
      final Map<String, Object?> merged = ConflictPolicy.clientWins.resolve(
        const <String, Object?>{},
        remote,
      );
      expect(merged, remote);
    });
  });

  group('ConflictPolicy.custom — wraps a user resolver', () {
    test('delegates to the wrapped resolver', () {
      final ConflictPolicy policy = ConflictPolicy.custom(
        (Map<String, Object?> local, Map<String, Object?> remote) =>
            <String, Object?>{...local, ...remote, 'merged_by': 'custom'},
      );
      final Map<String, Object?> merged = policy.resolve(
        <String, Object?>{'a': 1},
        <String, Object?>{'b': 2},
      );
      expect(
        merged,
        <String, Object?>{'a': 1, 'b': 2, 'merged_by': 'custom'},
      );
    });

    test('plugs in MergeStrategies.preferLocalColumns', () {
      final ConflictPolicy policy = ConflictPolicy.custom(
        MergeStrategies.preferLocalColumns(<String>['display_name']),
      );
      final Map<String, Object?> merged = policy.resolve(
        <String, Object?>{'display_name': 'A', 'role': 'user'},
        <String, Object?>{'display_name': 'B', 'role': 'admin'},
      );
      // local wins on display_name; remote wins on role.
      expect(
        merged,
        <String, Object?>{'display_name': 'A', 'role': 'admin'},
      );
    });

    test('plugs in MergeStrategies.maxOf for counters', () {
      final ConflictPolicy policy = ConflictPolicy.custom(
        MergeStrategies.maxOf(<String>['view_count']),
      );
      final Map<String, Object?> merged = policy.resolve(
        <String, Object?>{'view_count': 5, 'title': 'A'},
        <String, Object?>{'view_count': 10, 'title': 'B'},
      );
      // maxOf on view_count; LWW (remote) on title.
      expect(
        merged,
        <String, Object?>{'view_count': 10, 'title': 'B'},
      );
    });
  });

  group('Back-compat — old API still works', () {
    test('LwwConflictResolver.instance behaves like ConflictPolicy.lww', () {
      final ConflictResolver oldApi = LwwConflictResolver.instance;
      final Map<String, Object?> oldMerged = oldApi(
        <String, Object?>{'a': 1, 'b': 2},
        <String, Object?>{'b': 99, 'c': 3},
      );
      final Map<String, Object?> newMerged = ConflictPolicy.lww.resolve(
        <String, Object?>{'a': 1, 'b': 2},
        <String, Object?>{'b': 99, 'c': 3},
      );
      expect(oldMerged, newMerged);
    });

    test('CustomConflictResolver.wrap is the identity on a resolver', () {
      final ConflictResolver wrapped = CustomConflictResolver.wrap(
        (Map<String, Object?> local, Map<String, Object?> remote) =>
            <String, Object?>{...local, ...remote, 'x': 1},
      );
      final Map<String, Object?> merged = wrapped(
        <String, Object?>{'a': 1},
        <String, Object?>{'b': 2},
      );
      expect(merged, <String, Object?>{'a': 1, 'b': 2, 'x': 1});
    });
  });
}
