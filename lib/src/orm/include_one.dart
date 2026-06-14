//: `IncludeOne` subtype of the sealed
// [IncludeRelation]. This file is a `part of`
// `include_relation.dart` (Dart 3 sealed
// restriction: all subtypes must be in the same
// library).

part of 'include_relation.dart';

class IncludeOne<T, R> extends IncludeRelation<T, R> {
  /// The FK column on `T` (the table-side name,
  /// e.g. `'author_id'`). The related row's PK
  /// (`relatedTable.id`) is matched against
  /// `T.<this>`.
  final String fkColumnOnT;

  const IncludeOne({
    required super.navigationName,
    required super.relatedMeta,
    required this.fkColumnOnT,
  });

  @override
  String toString() => 'IncludeOne<$T, $R>($navigationName → '
      '${relatedMeta.tableName} ON '
      '${relatedMeta.tableName}.id = $fkColumnOnT)';
}
