import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('FormValueParser', () {
    test('converts a numeric raw value through the provided parser', () {
      final FormValueParser<int> parser = FormValueParser<int>(
        parse: (Object? rawValue) => int.parse(rawValue! as String),
      );

      expect(parser.parse('42'), 42);
    });

    test('converts an ISO date raw value through the provided parser', () {
      final FormValueParser<DateTime> parser = FormValueParser<DateTime>(
        parse: (Object? rawValue) => DateTime.parse(rawValue! as String),
      );

      expect(parser.parse('2026-11-17T12:30:00Z'), isA<DateTime>());
    });
  });
}
