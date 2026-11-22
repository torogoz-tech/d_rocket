import 'dart:async';

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('RestQueryCache', () {
    test('resolves supported tag placeholders without evaluating code', () {
      expect(
        resolveRestQueryTemplate(
          'account:{id}:{request.sourceId}',
          <String, Object?>{
            'id': '123',
            'request.sourceId': '456',
          },
        ),
        'account:123:456',
      );
    });

    test('deduplicates concurrent loads and shares the result', () async {
      final RestQueryCache cache = RestQueryCache();
      final Completer<void> gate = Completer<void>();
      var loads = 0;

      Future<String> load() async {
        loads++;
        await gate.future;
        return 'account';
      }

      final Stream<String> first = cache.watch<String>(
        key: 'GET /accounts/1',
        tags: const <String>['account:1'],
        loader: load,
      );
      final Stream<String> second = cache.watch<String>(
        key: 'GET /accounts/1',
        tags: const <String>['account:1'],
        loader: load,
      );
      final Future<List<String>> firstResult = first.take(1).toList();
      final Future<List<String>> secondResult = second.take(1).toList();

      await Future<void>.delayed(Duration.zero);
      expect(loads, 1);
      gate.complete();

      expect(await firstResult, <String>['account']);
      expect(await secondResult, <String>['account']);
    });

    test('reuses a fresh value and refetches after tag invalidation', () async {
      final RestQueryCache cache = RestQueryCache();
      var loads = 0;

      Future<int> load() async => ++loads;

      final Stream<int> stream = cache.watch<int>(
        key: 'GET /counter',
        tags: const <String>['counter'],
        loader: load,
        staleTime: const Duration(minutes: 1),
      );
      final Completer<int> firstValue = Completer<int>();
      final StreamSubscription<int> subscription = stream.listen((int value) {
        if (!firstValue.isCompleted) {
          firstValue.complete(value);
        }
      });
      expect(await firstValue.future, 1);
      expect(await cache.watch<int>(
        key: 'GET /counter',
        tags: const <String>['counter'],
        loader: load,
        staleTime: const Duration(minutes: 1),
      ).take(1).first, 1);
      expect(loads, 1);

      final Completer<int> refreshed = Completer<int>();
      final StreamSubscription<int> refreshedSubscription =
          stream.listen((int value) {
        if (value == 2 && !refreshed.isCompleted) {
          refreshed.complete(value);
        }
      });
      await cache.invalidate(const <String>['counter']);
      expect(await refreshed.future, 2);
      expect(loads, 2);
      await subscription.cancel();
      await refreshedSubscription.cancel();
    });

    test('clear prevents a late response from repopulating the cache', () async {
      final RestQueryCache cache = RestQueryCache();
      final Completer<String> gate = Completer<String>();
      final Stream<String> stream = cache.watch<String>(
        key: 'GET /secret',
        tags: const <String>['secret'],
        loader: () => gate.future,
      );
      final Future<List<String>> values = stream.toList();

      await Future<void>.delayed(Duration.zero);
      await cache.clear();
      gate.complete('must-not-leak');
      await Future<void>.delayed(Duration.zero);

      expect(cache.entryCount, 0);
      await expectLater(values, completes);
    });

    test('propagates loader errors to subscribers', () async {
      final RestQueryCache cache = RestQueryCache();
      final Stream<String> stream = cache.watch<String>(
        key: 'GET /failure',
        tags: const <String>['failure'],
        loader: () async => throw StateError('offline'),
      );

      await expectLater(stream, emitsError(isA<StateError>()));
    });
  });
}
