// + .2e (split): read-only view
// of the [Serializer] registry. Returned by
// [Serializer.snapshot] for debugging and testing.
//
// This file is a `part of` [serializer.dart] because
// the private `_` constructor must be callable from
// the same library.

part of 'serializer.dart';

class SerializerSnapshot {
  const SerializerSnapshot._({
    required this.factories,
    required this.encoders,
    required this.unionTypeFields,
    required this.unionFactories,
  });

  final Map<Type, JsonFactory<dynamic>> factories;
  final Map<Type, JsonEncoder<dynamic>> encoders;
  final Map<Type, String> unionTypeFields;
  final Map<Type, Map<String, JsonFactory<dynamic>>> unionFactories;

  Iterable<Type> get registeredTypes => factories.keys;

  Map<Type, Map<String, JsonFactory<dynamic>>> get unions => unionFactories;
}
