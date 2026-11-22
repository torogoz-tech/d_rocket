import 'package:d_rocket/d_rocket.dart';

part 'read_value_model.d_rocket_serializer.g.dart';

Object? readDisplayName(Map<String, dynamic> json) => json['display_name'];

@Serializable()
class ReadValueModel {
  const ReadValueModel({required this.displayName});

  @JsonKey(readValue: 'readDisplayName')
  final String displayName;
}
