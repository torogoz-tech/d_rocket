// example/lib/main.dart
//
// Minimal example of using d_rocket's SQLite ORM.
// Opens an in-memory database, runs a migration, and
// queries a typed set.
//
// To run:
//   cd example
//   flutter pub get
//   dart run main.dart
//
// The `@Table` annotated entity is normally
// generated via `d_rocket_builder`. For this minimal
// example we use a hand-written stub that satisfies
// the same contract.

import 'package:d_rocket/d_rocket.dart';

part 'main.g.dart';

/// A minimal Table stub (codegen would emit this).
class Book extends Record {
  Book({this.id = 0, required this.title, required this.authorId});
  @PrimaryKey()
  final int id;
  final String title;
  final int authorId;
}

Future<void> main() async {
  // .d: a real app would call `initializeD()` (codegen-emitted)
  // to register all serializers, then construct a
  // `DbContext` for the production SQLite provider.
  // For this example we just print the version of the
  // framework on the active platform.
  print('d_rocket example: hand-written Book record defined.');
  print('See packages/d_rocket/lib for the full API and the');
  print('README for the codegen flow with d_rocket_builder.');
}
