import 'package:d_rocket/d_rocket.dart';

part 'value_model.d_rocket_serializer.g.dart';

@Serializable(copyWith: true, equality: true)
class ValueModel with _$ValueModelEquality {
  const ValueModel({
    required this.id,
    required this.description,
    required this.labels,
  });

  final String id;
  final String? description;
  final List<String> labels;
}
