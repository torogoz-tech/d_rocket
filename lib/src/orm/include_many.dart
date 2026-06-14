//: `IncludeMany` subtype of the sealed
// [IncludeRelation]. This file is a `part of`
// `include_relation.dart` (Dart 3 sealed
// restriction: all subtypes must be in the same
// library).

part of 'include_relation.dart';

class IncludeMany<T, R> extends IncludeRelation<T, R> {
  /// The FK column on the related table
  /// (e.g. `'book_id'`). Each row where
  /// `relatedTable.<this> = T.id` is included.
  final String inverseFkColumn;

  const IncludeMany({
    required super.navigationName,
    required super.relatedMeta,
    required this.inverseFkColumn,
  });

  @override
  String toString() => 'IncludeMany<$T, $R>($navigationName ← '
      '${relatedMeta.tableName} ON '
      '${relatedMeta.tableName}.$inverseFkColumn = '
      '$navigationName.id)';
}
