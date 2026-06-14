// Regression tests for the default values of the
// annotation classes in lib/src/serializer/.
//
// The documentation (`docs/04-layer-1-serialization.md`)
// and the `CHANGELOG.md` both state these defaults
// explicitly. If a default ever changes, the test
// fails before the docs go stale.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  group('@Serializable defaults', () {
    test('unknownKeyPolicy defaults to ignore (not strict, not lenient)', () {
      const ann = Serializable();
      expect(ann.unknownKeyPolicy, UnknownKeyPolicy.ignore);
    });

    test('naming defaults to none', () {
      const ann = Serializable();
      expect(ann.naming, JsonNaming.none);
    });

    test('rename, discriminator, and typeField default to null', () {
      const ann = Serializable();
      expect(ann.rename, isNull);
      expect(ann.discriminator, isNull);
      expect(ann.typeField, isNull);
    });
  });

  group('@SerializableUnion defaults', () {
    test('typeField defaults to "type"', () {
      const ann = SerializableUnion();
      expect(ann.typeField, 'type');
    });
  });

  group('@JsonKey defaults', () {
    test('name defaults to null', () {
      const ann = JsonKey();
      expect(ann.name, isNull);
    });

    test('ignore defaults to false', () {
      const ann = JsonKey();
      expect(ann.ignore, isFalse);
    });

    test('requiredKey defaults to false', () {
      const ann = JsonKey();
      expect(ann.requiredKey, isFalse);
    });

    test('useEnumIndex defaults to false', () {
      const ann = JsonKey();
      expect(ann.useEnumIndex, isFalse);
    });

    test('defaultValue defaults to null', () {
      const ann = JsonKey();
      expect(ann.defaultValue, isNull);
    });

    test('converter defaults to null', () {
      const ann = JsonKey();
      expect(ann.converter, isNull);
    });

    test('unknownEnumValue defaults to null', () {
      const ann = JsonKey();
      expect(ann.unknownEnumValue, isNull);
    });
  });

  group('JsonNaming enum', () {
    test('has 5 values, including pascalCase', () {
      expect(JsonNaming.values, <JsonNaming>{
        JsonNaming.none,
        JsonNaming.snakeCase,
        JsonNaming.camelCase,
        JsonNaming.kebabCase,
        JsonNaming.pascalCase,
      });
    });
  });

  group('UnknownKeyPolicy enum', () {
    test('has 3 values: strict, ignore, capture (no lenient)', () {
      expect(UnknownKeyPolicy.values, <UnknownKeyPolicy>{
        UnknownKeyPolicy.strict,
        UnknownKeyPolicy.ignore,
        UnknownKeyPolicy.capture,
      });
    });
  });
}
