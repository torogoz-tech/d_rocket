/// Marca una clase abstracta como cliente HTTP tipado generado por
/// `d_rocket_builder`.
///
/// Ejemplo:
/// ```dart
/// @RestClient(baseUrl: 'https://api.example.com')
/// abstract class ApiClient {
/// @HttpGet('/users')
/// Future<List`<User>`> getUsers;
/// }
/// ```
class RestClient {
  /// URL base aplicada a todos los métodos. Si es relativa, se combina
  /// con la [baseUrl] del registry.
  final String baseUrl;

  /// Headers aplicados a todos los métodos (se sobreescriben por
  /// los headers de método o de parámetro).
  final Map<String, String> headers;

  /// Timeout por defecto para todas las llamadas.
  final Duration? timeout;

  const RestClient({
    this.baseUrl = '',
    this.headers = const <String, String>{},
    this.timeout,
  });
}

/// Prefijo de ruta aplicado a nivel de clase (estilo `[Route]` de
/// ASP.NET Core).
///
/// ```dart
/// @RestClient(baseUrl: 'https://api.x.com')
/// @Route('/api/v1/todos')
/// abstract class TodoClient {
/// @HttpGet // -> GET https://api.x.com/api/v1/todos
/// Future<List`<Todo>`> getAll;
/// }
/// ```
class Route {
  final String path;

  /// Anula la `baseUrl` del registry. Útil cuando se necesita apuntar
  /// a otro host para un cliente en particular.
  final String? baseUrl;

  const Route(this.path, {this.baseUrl});
}
