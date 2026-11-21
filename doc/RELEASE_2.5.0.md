# d_rocket 2.5.0

## Validación de UUID

Los modelos de formularios pueden reemplazar expresiones regulares repetidas
por una anotación explícita:

```dart
@Required()
@Uuid(version: UuidVersion.v4)
final String requestId;
```

`@Uuid()` acepta UUID canónicos con versiones 1 a 8. El parámetro opcional
`version` restringe el nibble de versión a `UuidVersion.v1` hasta
`UuidVersion.v8`. La validación acepta mayúsculas y minúsculas, exige guiones,
comprueba la variante RFC compatible y conserva `message` y `code` para
localización y telemetría.

La anotación valida valores existentes; no genera UUIDs. Para generar un UUID
v4 se mantiene disponible `generateUuidV4()`.
