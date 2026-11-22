# d_rocket 2.6 benchmarks

Run the reproducible local benchmark with:

```sh
dart run tool/benchmarks/d_rocket_2_6_benchmark.dart 1000
```

The command reports elapsed microseconds and cache loader counts for the
reactive REST cache and JSON serialization. It is diagnostic only; release
comparisons should use the same Dart SDK, machine and iteration count.
