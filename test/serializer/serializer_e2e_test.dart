//: E2E tests for the Serializer
// with nested types, lists of maps, and unions.
// Verifies the codec chain handles complex
// shapes (not just the shape-only tests in
// `absorbed_serializer_test.dart`).

import 'package:d_rocket/d_rocket.dart';
import 'package:test/test.dart';

void main() {
  setUp(Serializer.reset);
  tearDown(Serializer.reset);

  group('Fase 6.3 — Serializer: nested types', () {
    test('a class with a List<OtherClass> field round-trips', () {
      Serializer.register<Author>(
        fromJson: (Map<String, dynamic> json) => Author(
          json['id']! as int,
          json['name']! as String,
        ),
        toJson: (Author a) => <String, dynamic>{'id': a.id, 'name': a.name},
      );
      Serializer.register<Book>(
        fromJson: (Map<String, dynamic> json) => Book(
          json['id']! as int,
          json['title']! as String,
          (json['authors']! as List)
              .map((dynamic e) => Serializer.fromDynamic<Author>(
                    e as Map<String, dynamic>,
                  ))
              .toList(),
        ),
        toJson: (Book b) => <String, dynamic>{
          'id': b.id,
          'title': b.title,
          'authors': b.authics.map((Author a) => a.toJson()).toList(),
        },
      );
      final Book b = Book(
        1,
        'Rex',
        <Author>[Author(1, 'Alice'), Author(2, 'Bob')],
      );
      final String json = Serializer.toJson<Book>(b);
      expect(json, contains('"id":1'));
      expect(json, contains('"title":"Rex"'));
      expect(json, contains('"name":"Alice"'));
      expect(json, contains('"name":"Bob"'));
      final Book round = Serializer.fromJson<Book>(json);
      expect(round.id, 1);
      expect(round.title, 'Rex');
      expect(round.authics, hasLength(2));
      expect(round.authics[0].name, 'Alice');
      expect(round.authics[1].name, 'Bob');
    });

    test('a class with a Map<String, OtherClass> round-trips', () {
      Serializer.register<Author>(
        fromJson: (Map<String, dynamic> json) => Author(
          json['id']! as int,
          json['name']! as String,
        ),
        toJson: (Author a) => <String, dynamic>{'id': a.id, 'name': a.name},
      );
      Serializer.register<Libreria>(
        fromJson: (Map<String, dynamic> json) => Libreria(
          (json['books']! as Map<String, dynamic>).map(
            (String k, dynamic v) => MapEntry<String, Author>(
              k,
              Serializer.fromDynamic<Author>(
                v as Map<String, dynamic>,
              ),
            ),
          ),
        ),
        toJson: (Libreria l) => <String, dynamic>{
          'books': l.byIsbn.map(
              (String k, Author a) => MapEntry<String, dynamic>(k, a.toJson())),
        },
      );
      final Libreria lib = Libreria(
        <String, Author>{
          '978-0-1': Author(1, 'Alice'),
          '978-0-2': Author(2, 'Bob'),
        },
      );
      final String json = Serializer.toJson<Libreria>(lib);
      expect(json, contains('978-0-1'));
      expect(json, contains('978-0-2'));
      final Libreria round = Serializer.fromJson<Libreria>(json);
      expect(round.byIsbn['978-0-1']!.name, 'Alice');
      expect(round.byIsbn['978-0-2']!.name, 'Bob');
    });
  });

  group('Fase 6.3 — Serializer: encodeDynamic (codec chain)', () {
    test('List<Map<String, primitive>> round-trips', () {
      final List<Map<String, Object?>> data = <Map<String, Object?>>[
        <String, Object?>{'id': 1, 'name': 'Alice'},
        <String, Object?>{'id': 2, 'name': 'Bob'},
      ];
      final Object? encoded = Serializer.encodeDynamic(data);
      expect(encoded, isA<List<dynamic>>());
      final List<dynamic> list = encoded! as List<dynamic>;
      expect(list, hasLength(2));
      expect((list[0] as Map<String, dynamic>)['id'], 1);
    });

    test('deeply nested: List<List<DateTime>> encodes correctly', () {
      final List<List<DateTime>> data = <List<DateTime>>[
        <DateTime>[DateTime.utc(2026, 1, 1)],
        <DateTime>[DateTime.utc(2026, 6, 1)],
      ];
      final Object? encoded = Serializer.encodeDynamic(data);
      final List<dynamic> outer = encoded! as List<dynamic>;
      expect((outer[0] as List<dynamic>)[0], isA<String>());
    });
  });

  group('Fase 6.3 — Serializer: unions (polymorphic)', () {
    test('a union with 3 discriminators resolves correctly', () {
      Serializer.registerUnion<Animal>(
        typeField: 'kind',
        discriminator: 'dog',
        fromJson: (Map<String, dynamic> json) => Dog(json['name']! as String),
      );
      Serializer.registerUnion<Animal>(
        typeField: 'kind',
        discriminator: 'cat',
        fromJson: (Map<String, dynamic> json) => Cat(json['name']! as String),
      );
      Serializer.registerUnion<Animal>(
        typeField: 'kind',
        discriminator: 'fish',
        fromJson: (Map<String, dynamic> json) =>
            Fish(json['species']! as String),
      );
      final Animal dog = Serializer.fromDynamic<Animal>(<String, dynamic>{
        'kind': 'dog',
        'name': 'Rex',
      });
      expect(dog, isA<Dog>());
      final Animal cat = Serializer.fromDynamic<Animal>(<String, dynamic>{
        'kind': 'cat',
        'name': 'Whiskers',
      });
      expect(cat, isA<Cat>());
      final Animal fish = Serializer.fromDynamic<Animal>(<String, dynamic>{
        'kind': 'fish',
        'species': 'Clown',
      });
      expect(fish, isA<Fish>());
    });

    test('a union with an unknown discriminator throws', () {
      Serializer.registerUnion<Animal>(
        typeField: 'kind',
        discriminator: 'dog',
        fromJson: (Map<String, dynamic> json) => Dog(json['name']! as String),
      );
      expect(
        () => Serializer.fromDynamic<Animal>(<String, dynamic>{
          'kind': 'dragon',
          'name': 'Smaug',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}

class Author {
  const Author(this.id, this.name);
  final int id;
  final String name;
  Map<String, dynamic> toJson() => <String, dynamic>{'id': id, 'name': name};
}

class Book {
  const Book(this.id, this.title, this.authics);
  final int id;
  final String title;
  final List<Author> authics;
}

class Libreria {
  const Libreria(this.byIsbn);
  final Map<String, Author> byIsbn;
}

sealed class Animal {
  const Animal();
}

class Dog extends Animal {
  const Dog(this.name);
  final String name;
}

class Cat extends Animal {
  const Cat(this.name);
  final String name;
}

class Fish extends Animal {
  const Fish(this.species);
  final String species;
}
