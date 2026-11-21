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

## WebSocket robusto

`WebSocketReconnector` puede resolver headers asíncronos antes de cada
conexión, publicar sus estados (`connecting`, `connected`, `retrying`,
`stopped` y `failed`) y recuperar un `401` mediante `onUnauthorized`. Los
`403` son terminales, el contador se reinicia solo después de conectar con
éxito y `inactivityTimeout` considera el tráfico de heartbeat. `stop()`
cancela timers, suscripciones y conexiones pendientes; `start()` puede
utilizarse nuevamente y `dispose()` cierra también los streams públicos.

## Errores REST tipados

`RestHttpException.problem` ofrece una vista `RestProblemDetails` de payloads
RFC 7807, con `validationErrors`, código de negocio y metadatos de correlación.
Los headers de respuesta `traceId` y `requestId` también quedan disponibles.
El acceso original `problemDetails` continúa disponible para extensiones
específicas del backend.

## Diagnostics y codegen

Los reconnectores publican eventos `websocket.state` correlacionados con el
estado, intento, status HTTP y contexto de cierre. Los bodies y errores de
validación permanecen ocultos salvo que se habilite explícitamente la captura
de datos sensibles. El pipeline regenera los `.g.dart` y ejecuta
`dart run tool/verify_generated.dart` antes del análisis para detectar tokens
sin expandir, doble nulabilidad, casts nulos de `DateTime` y listas default
con `<dynamic>`.

## Validación entre campos

Los validadores de nivel de modelo de `FormState<T>` se ejecutan después de
las validaciones de campo y permiten reglas como confirmar contraseñas o
calcular la longitud del CVV según la marca. `bindComposite()` mantiene el
binding de controles que alimentan más de una propiedad.

## Validación asíncrona

Los adaptadores generados aceptan `AsyncFormValidator<T>` y exponen
`validateAsync()` y `buildAsync()`. `FormFieldState` y `FormState` publican
`FormValidationState.validating`, `valid` e `invalid`; el debounce evita
solicitudes remotas por cada pulsación.

```dart
final form = LoginRequestForm(
  asyncValidators: <AsyncFormValidator<LoginRequest>>[
    (LoginRequest? value) => checkEmailAvailability(value?.email),
  ],
  asyncValidationDebounce: const Duration(milliseconds: 300),
);
```

Un `RestHttpException` puede aplicarse directamente al formulario mediante
`form.applyRestError(error)`, mapeando `problem.errors` a los campos generados.

## Diagnóstico de serialización

Las conversiones generadas ahora lanzan `SerializationException` con el campo,
tipo esperado, valor recibido y causa original. Se mantienen las políticas
explícitas `UnknownKeyPolicy.strict`, `ignore` y `capture`; las fechas,
decimales equivalentes (`double`/`num`), enums y UUID continúan usando sus
contratos declarativos existentes.

## Compatibilidad

El workflow `Compatibility` regenera y prueba el paquete con Dart 3.11.5,
3.12.0 y 3.13.0 junto con Flutter estable. Su ejecución manual puede activar
la comprobación de resolución exclusiva desde pub.dev para los paquetes 2.5.0.
