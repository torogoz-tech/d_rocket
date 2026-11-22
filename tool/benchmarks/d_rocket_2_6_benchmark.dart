import 'dart:async';
import 'dart:convert' as convert;
import 'dart:io';

import 'package:d_rocket/d_rocket.dart';

Future<void> main(List<String> args) async {
  final int iterations = int.tryParse(args.firstOrNull ?? '') ?? 1000;
  final Map<String, Object?> results = <String, Object?>{
    'iterations': iterations,
    'cache': await _benchmarkCache(iterations),
    'serialization': _benchmarkSerialization(iterations),
  };
  stdout.writeln(const convert.JsonEncoder.withIndent('  ').convert(results));
}

Future<Map<String, Object?>> _benchmarkCache(int iterations) async {
  final RestQueryCache cache = RestQueryCache();
  int loads = 0;
  final Stopwatch stopwatch = Stopwatch()..start();
  for (int index = 0; index < iterations; index++) {
    final StreamSubscription<int> subscription = cache
        .watch<int>(
          key: 'GET /items/$index',
          tags: <String>['items'],
          loader: () async {
            loads++;
            return index;
          },
        )
        .listen((_) {});
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();
  }
  stopwatch.stop();
  await cache.clear();
  return <String, Object?>{
    'microseconds': stopwatch.elapsedMicroseconds,
    'loads': loads,
  };
}

Map<String, Object?> _benchmarkSerialization(int iterations) {
  final List<Object?> payload = <Object?>[
    <String, Object?>{'id': '1', 'active': true, 'amount': 10.5},
  ];
  final Stopwatch stopwatch = Stopwatch()..start();
  for (int index = 0; index < iterations; index++) {
    convert.jsonEncode(payload);
  }
  stopwatch.stop();
  return <String, Object?>{
    'microseconds': stopwatch.elapsedMicroseconds,
  };
}
