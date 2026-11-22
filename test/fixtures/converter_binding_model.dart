import 'package:d_rocket/d_rocket.dart';

part 'converter_binding_model.d_rocket_serializer.g.dart';

const JsonConverter<DateTime, String> isoDateConverter =
    JsonConverter<DateTime, String>(
  fromJson: DateTime.parse,
  toJson: _encodeIsoDate,
);

String _encodeIsoDate(DateTime value) => 'custom:${value.toIso8601String()}';

@JsonConverterBinding(typeName: 'DateTime', converter: 'isoDateConverter')
@Serializable()
class ConverterBindingModel {
  const ConverterBindingModel({required this.when});

  final DateTime when;
}
