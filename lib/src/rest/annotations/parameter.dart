/// Anotaciones a nivel de parámetro. Determinan de dónde sale el valor.
///
/// - [Body]: cuerpo de la petición (se serializa a JSON con `d_serializer`).
/// - [Query]: query string `?name=value`.
/// - [Path]: segmento de ruta `{name}`.
/// - [Header]: header HTTP.
/// - [Field]: form-urlencoded.
/// - [Part]: multipart.
sealed class Parameter {
  final String? name;
  const Parameter({this.name});
}

/// El argumento se serializa como cuerpo de la petición (JSON).
class Body extends Parameter {
  const Body();
}

/// El argumento se envía como `?{name}={value}`. Si `name` es `null` se
/// usa el nombre del parámetro en el código Dart.
// Each annotation child (Query, Path, ...) re-declares
// the `name` field that [Parameter] already declares. The
// `lints/recommended` rule `overridden_fields` flags this,
// but the alternative (using `super.name` in a positional
// constructor) doesn't work because [Parameter]'s `name`
// is a NAMED parameter, not a positional one. Keeping
// the field is the lowest-friction option for the public
// API.
// ignore_for_file: overridden_fields

class Query extends Parameter {
  const Query([this.name]);
  @override
  final String? name;
}

/// El argumento reemplaza un `{name}` en la ruta del método.
class Path extends Parameter {
  const Path([this.name]);
  @override
  final String? name;
}

/// El argumento se envía como header HTTP (`name` o `name: value`).
class Header extends Parameter {
  const Header([this.name]);
  @override
  final String? name;
}

/// El argumento se envía como `application/x-www-form-urlencoded`.
class Field extends Parameter {
  const Field([this.name]);
  @override
  final String? name;
}

/// El argumento se envía como parte de `multipart/form-data`.
class Part extends Parameter {
  const Part([this.name]);
  @override
  final String? name;
}

/// Cuerpo crudo (`String` o `List<int>`). Se envía tal cual sin
/// serializar como JSON.
class RawBody extends Parameter {
  const RawBody();
}
