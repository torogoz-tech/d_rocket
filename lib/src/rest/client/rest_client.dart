import 'package:d_rocket/d_rocket.dart';

/// Configuración global del runtime `d_rocket` (capa 2 — REST with
/// steroids). Suele haber una sola instancia por aplicación
/// ([dRest]).
class RestConfig {
  HttpClient httpClient;
  final List<RestInterceptor> interceptors;
  final Duration defaultTimeout;
  final Map<String, String> defaultHeaders;

  RestConfig({
    HttpClient? httpClient,
    this.interceptors = const <RestInterceptor>[],
    this.defaultTimeout = const Duration(seconds: 30),
    this.defaultHeaders = const <String, String>{},
  }) : httpClient = httpClient ?? HttpPackageClient();
}

/// Singleton accesible como `dRest.client`, `dRest.config`, etc.
class DRest {
  DRest._();
  static final DRest instance = DRest._();

  RestConfig _config = RestConfig();
  RestConfig get config => _config;

  HttpClient get client => _config.httpClient;

  /// Inicializa el runtime con un cliente HTTP y los interceptors
  /// opcionales.
  ///
  /// Pasar un [httpClient] propio permite usar implementaciones
  /// alternativas (por ejemplo, basadas en `dio`) sin perder los
  /// interceptors. Si se omite, se usa `HttpPackageClient`.
  void useDefaults({
    HttpClient? httpClient,
    List<RestInterceptor> interceptors = const <RestInterceptor>[],
    Duration defaultTimeout = const Duration(seconds: 30),
    Map<String, String> defaultHeaders = const <String, String>{},
  }) {
    final HttpClient client = httpClient ??
        HttpPackageClient(
          client: null,
          interceptors: interceptors,
        );
    _config = RestConfig(
      httpClient: client,
      interceptors: interceptors,
      defaultTimeout: defaultTimeout,
      defaultHeaders: defaultHeaders,
    );
  }

  /// Reemplaza el [HttpClient] en tiempo de ejecución (útil para
  /// tests o para usar una implementación basada en `dio`).
  set client(HttpClient client) {
    _config.httpClient = client;
  }

  /// Helpers de instancia que el codegen invoca para (de)serializar
  /// bodies usando el `Serializer` reexportado por d_rocket
  /// (originalmente de d_serializer).
  String encodeBody<T>(T value) => Serializer.toJson<T>(value);
  T decodeBody<T>(dynamic data) => Serializer.fromDynamic<T>(data);
}

/// Acceso de azúcar: `dRest.client`, `dRest.config`, etc.
final DRest dRest = DRest.instance;

/// Helper que se llama desde el código generado para invocar el
/// cliente con la respuesta adecuada.
///
/// Devuelve `null` cuando el body es `null` y el tipo `T` lo permite
/// (detección de nulabilidad con `null is T`, válida en tiempo de
/// ejecución en Dart). Para tipos no-nullable, una respuesta con body
/// `null` se decodifica llamando al [decoder] con `null`, lo que
/// permite al decoder decidir qué hacer (lanzar, devolver un valor
/// por defecto, etc.).
Future<T> invokeRequest<T>(
  RestRequest request,
  Decoder<dynamic> decoder,
) async {
  final HttpClient client = dRest.client;
  final RestResponse<dynamic> raw = await client.execute(
    request,
    decoder: decoder,
  );

  // Caso 1: body null y T nullable → devolver null.
  if (raw.body == null && null is T) {
    return null as T;
  }

  // Caso 2: body ya del tipo correcto (o subtipo) → cast directo.
  if (raw.body is T) {
    return raw.body as T;
  }

  // Caso 3: dejar que el decoder decida.
  return decoder(raw.body) as T;
}
