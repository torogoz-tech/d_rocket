/// Shared test model used by the LINQ tests.
library;

import 'package:d_rocket/d_rocket.dart';

class User implements RecordLike {
  User({
    required this.id,
    required this.name,
    required this.age,
    this.email,
  });

  final int id;
  final String name;
  final int age;
  final String? email;

  @override
  Object? readField(String fieldName) => switch (fieldName) {
        'id' => id,
        'name' => name,
        'age' => age,
        'email' => email,
        _ => null,
      };

  @override
  String toString() => 'User(id: $id, name: "$name", age: $age, email: $email)';
}
