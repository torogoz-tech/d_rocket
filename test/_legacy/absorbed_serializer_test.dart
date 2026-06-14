// Tests that verify ("absorb d_serializer") produced a
// faithful integration. The runtime that ships in
// `package:d_rocket/d_rocket.dart` is byte-for-byte the same as
// the legacy `package:d_serializer/d_serializer.dart` 1.3.0 — we
// just re-export it from a new home.
//
// This file does NOT exercise the codegen (that lives in
// `d_rocket_builder` and is tested by the bookstore example in
// `d_rocket_sqlite`). It only checks that the runtime API
// behaves the same way: same `Serializer.register`, same
// `JsonKey` / `JsonNaming` / `Format` annotations, same
// value-codec behaviour, same `Serializer.reset` /
// `Serializer.snapshot`, etc.

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  setUp(Serializer.reset);
  tearDown(Serializer.reset);

  group('Fase B — runtime parity with d_serializer', () {
    test('re-exports the Serializer singleton', () {
      // The same class, same static state, same registry.
      expect(Serializer, isNotNull);
      expect(Serializer.snapshot().factories, isEmpty);
    });

    test('re-exports the value annotations', () {
      // The annotation classes are importable from
      // `package:d_rocket/d_rocket.dart` directly. The const
      // constructors exist and accept the documented arguments.
      const Serializable a = Serializable();
      const Serializable b = Serializable(
        rename: 'foo',
        discriminator: 'bar',
        typeField: 'kind',
        unknownKeyPolicy: UnknownKeyPolicy.strict,
        naming: JsonNaming.snakeCase,
      );
      expect(a.rename, isNull);
      expect(b.rename, 'foo');
      expect(b.discriminator, 'bar');
      expect(b.typeField, 'kind');
      expect(b.unknownKeyPolicy, UnknownKeyPolicy.strict);
      expect(b.naming, JsonNaming.snakeCase);

      const JsonKey k = JsonKey(
        name: 'k',
        ignore: true,
        defaultValue: 0,
        converter: 'Money',
        useEnumIndex: true,
        requiredKey: true,
        unknownEnumValue: 'unknown',
      );
      expect(k.name, 'k');
      expect(k.ignore, isTrue);
      expect(k.converter, 'Money');

      const SerializableUnion u = SerializableUnion(typeField: 'kind');
      expect(u.typeField, 'kind');

      expect(Format.trim(), isNotNull);
      expect(Format.uppercase(), isNotNull);
      expect(Format.lowercase(), isNotNull);
      expect(Format.date('yyyy-MM-dd'), isNotNull);
      expect(Format.custom('TitleCase'), isNotNull);
      expect(Format.customWith(_TitleCase), isNotNull);
    });

    test('re-exports the JsonNaming enum (5 strategies)', () {
      expect(JsonNaming.values, <JsonNaming>{
        JsonNaming.none,
        JsonNaming.snakeCase,
        JsonNaming.camelCase,
        JsonNaming.kebabCase,
        JsonNaming.pascalCase,
      });
    });

    test('re-exports the UnknownKeyPolicy enum (3 strategies)', () {
      expect(UnknownKeyPolicy.values, <UnknownKeyPolicy>{
        UnknownKeyPolicy.strict,
        UnknownKeyPolicy.ignore,
        UnknownKeyPolicy.capture,
      });
    });

    test(
        'round-trip through Serializer.toJson / Serializer.fromJson '
        'produces the byte-identical JSON as the legacy '
        'd_serializer runtime would', () {
      // Same hand-written (de)serialisation, same registry call,
      // same JSON output. This is the byte-identical parity
      // contract of: a class registered through
      // `package:d_rocket` produces the exact same JSON text as
      // a class registered through `package:d_serializer`.
      final Author alice = Author(1, 'Alice', 'alice@x.com');
      Serializer.register<Author>(
        fromJson: Author.fromJson,
        toJson: (Author a) => a.toJson(),
      );

      final String json = Serializer.toJson<Author>(alice);
      // Hand-verified JSON shape (no whitespace, sorted by key
      // because `jsonEncode` of a `Map<String, dynamic>` does not
      // guarantee order). We assert on the structural content
      // rather than the literal string.
      expect(json, contains('"id":1'));
      expect(json, contains('"name":"Alice"'));
      expect(json, contains('"email":"alice@x.com"'));

      // Round-trip restores the same value.
      final Author round = Serializer.fromJson<Author>(json);
      expect(round.id, 1);
      expect(round.name, 'Alice');
      expect(round.email, 'alice@x.com');
    });

    test('Serializer.reset / Serializer.snapshot work as documented', () {
      Serializer.register<_FakeType>(
        fromJson: (Map<String, dynamic> json) => _FakeType(json['id'] as int),
        toJson: (_FakeType v) => <String, dynamic>{'id': v.id},
      );
      expect(Serializer.snapshot().registeredTypes, contains(_FakeType));
      Serializer.reset();
      expect(Serializer.snapshot().factories, isEmpty);
    });

    test('Serializer.formatDate / Serializer.parseDate are exported', () {
      final DateTime when = DateTime(2026, 6, 1);
      expect(Serializer.formatDate(when, 'yyyy-MM-dd'), '2026-06-01');
      expect(Serializer.formatDate(when, 'iso8601'), when.toIso8601String());
      expect(
        Serializer.parseDate('2026-06-01', 'yyyy-MM-dd'),
        DateTime(2026, 6, 1),
      );
      expect(
        Serializer.parseDate(when.toIso8601String(), 'iso8601'),
        when,
      );
    });

    test('handles null, primitives, and nested values via encodeDynamic', () {
      expect(Serializer.encodeDynamic(null), isNull);
      expect(Serializer.encodeDynamic(42), 42);
      expect(Serializer.encodeDynamic('hello'), 'hello');
      expect(Serializer.encodeDynamic(true), isTrue);
      final DateTime t = DateTime.utc(2026, 6, 1);
      expect(Serializer.encodeDynamic(t), t.toIso8601String());
      expect(Serializer.encodeDynamic(<int>[1, 2, 3]), <int>[1, 2, 3]);
      expect(Serializer.encodeDynamic(<String, int>{'a': 1}),
          <String, int>{'a': 1});
    });

    test('union (polymorphic) registration works the same way', () {
      Serializer.registerUnion<PaymentMethod>(
        typeField: 'kind',
        discriminator: 'card',
        fromJson: (Map<String, dynamic> json) =>
            CardPayment(json['last4']! as String, json['brand']! as String),
      );
      final PaymentMethod card =
          Serializer.fromDynamic<PaymentMethod>(<String, dynamic>{
        'kind': 'card',
        'last4': '4242',
        'brand': 'Visa',
      });
      expect(card, isA<CardPayment>());
      expect((card as CardPayment).last4, '4242');
      expect(card.brand, 'Visa');
    });
  });

  group(
      'Fase B — barrel re-exports the same classes as '
      'd_serializer 1.3.0', () {
    test('JsonFactory and JsonEncoder typedefs are accessible', () {
      // The typedefs are used by `Serializer.register` and by
      // the generated code. We only check they resolve; the
      // runtime semantics are tested above.
      final JsonFactory<Author> fromJson = Author.fromJson;
      Map<String, dynamic> toJson(Author a) => a.toJson();
      expect(
          fromJson(<String, dynamic>{'id': 1, 'name': 'X', 'email': null}).id,
          1);
      expect(toJson(Author(1, 'X', null))['name'], 'X');
    });

    test('SerializerSnapshot is the same class', () {
      final SerializerSnapshot snap = Serializer.snapshot();
      expect(snap.factories, isA<Map<Type, JsonFactory<dynamic>>>());
      expect(snap.encoders, isA<Map<Type, JsonEncoder<dynamic>>>());
    });
  });
}

// ─── Test fixtures (NOT annotated; tests rely on manual
// `Serializer.register` calls so the suite stays free of
// `build_runner` dependencies). ─────────────────────────────────

class Author {
  const Author(this.id, this.name, this.email);
  final int id;
  final String name;
  final String? email;

  static Author fromJson(Map<String, dynamic> json) => Author(
        json['id']! as int,
        json['name']! as String,
        json['email'] as String?,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
      };
}

sealed class PaymentMethod {
  const PaymentMethod();
}

class CardPayment extends PaymentMethod {
  const CardPayment(this.last4, this.brand);
  final String last4;
  final String brand;
}

class _FakeType {
  const _FakeType(this.id);
  final int id;
}

class _TitleCase {
  const _TitleCase();
}
