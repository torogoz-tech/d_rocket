import 'package:d_rocket/d_rocket.dart';

part 'generic_value_model.d_rocket_serializer.g.dart';

@Serializable(copyWith: true, equality: true)
class GenericValue<T> with _$GenericValueEquality<T> {
  const GenericValue({required this.data, this.message});

  final T? data;
  final String? message;
}
