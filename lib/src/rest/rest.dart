/// Barrel de la capa 2 (REST with steroids) de `d_rocket`.
library;

export 'annotations/annotations.dart';
export 'client/http_client.dart';
export 'client/http_package_client.dart';
export 'client/rest_client.dart';
export 'clients/cached_http_client.dart';
export 'clients/compressed_http_client.dart';
export 'clients/hmac_http_client.dart';
export 'clients/oauth2_http_client.dart';
export 'decoder.dart';
export 'error.dart';
export 'interceptor.dart';
export 'request_codec.dart';
export 'rest_request.dart';
export 'rest_response.dart';
export 'clients/gzip_codec_io.dart' if (dart.library.html) 'clients/gzip_codec_stub.dart' show gzipEncode, gzipDecode, isAvailable;
