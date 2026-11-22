import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  tearDown(Serializer.reset);

  test('registered converters take precedence over built-in codecs', () {
    Serializer.registerConverter<DateTime>(
      JsonConverter<DateTime, Object?>(
        fromJson: (Object? raw) => DateTime.parse(raw! as String),
        toJson: (DateTime value) => 'custom:${value.toIso8601String()}',
      ),
    );

    final DateTime decoded = Serializer.decodeWithConverter<DateTime>(
      '2026-01-02T03:04:05.000Z',
    );
    expect(decoded, DateTime.utc(2026, 1, 2, 3, 4, 5));
    expect(
      Serializer.encodeWithConverter<DateTime>(decoded),
      'custom:2026-01-02T03:04:05.000Z',
    );
  });

  test('unknown fields can be rejected or captured by generated policy', () {
    expect(UnknownKeyPolicy.values, contains(UnknownKeyPolicy.strict));
    expect(UnknownKeyPolicy.values, contains(UnknownKeyPolicy.capture));
  });
}
