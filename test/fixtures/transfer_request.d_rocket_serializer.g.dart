// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

part of 'transfer_request.dart';

// **************************************************************************
// SerializableGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: non_constant_identifier_names

TransferRequest TransferRequestFromJson(Map<String, dynamic> json) {
  return TransferRequest(
    sourceAccountId: Serializer.decodeField<String>(
        field: 'TransferRequest.sourceAccountId',
        raw: json['sourceAccountId'],
        decode: () => json['sourceAccountId'] as String),
  );
}

Map<String, dynamic> TransferRequestToJson(TransferRequest value) {
  return <String, dynamic>{
    'sourceAccountId': value.sourceAccountId,
  };
}

void registerTransferRequestSerializer() {
  Serializer.register<TransferRequest>(
    fromJson: TransferRequestFromJson,
    toJson: TransferRequestToJson,
  );
}

extension TransferRequestSerializer on TransferRequest {
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sourceAccountId': sourceAccountId,
    };
  }
}

Map<String, Object?> TransferRequestJsonSchema() {
  return <String, Object?>{
    '\$schema': 'https://json-schema.org/draft/2020-12/schema',
    'title': 'TransferRequest',
    'type': 'object',
    'properties': <String, Object?>{
      'sourceAccountId': <String, Object?>{'type': 'string'},
    },
    'required': <String>['sourceAccountId'],
  };
}
