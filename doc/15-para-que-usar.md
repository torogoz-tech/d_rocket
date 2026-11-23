# Para qué usar d_rocket

`d_rocket` es una capa de datos para aplicaciones Dart y Flutter que
necesitan mantener coherentes el modelo, el JSON, el transporte, la
persistencia local, la sincronización y los eventos en tiempo real.

No es necesario adoptar todo el framework. La unidad de adopción es la
capacidad: una aplicación puede empezar con serialización y REST, añadir
formularios después y activar SQLite o sincronización únicamente cuando el
producto lo necesite.

## Cuándo encaja especialmente bien

### Aplicaciones offline-first

Úsalo cuando la aplicación debe seguir leyendo y capturando datos sin
conectividad estable. SQLite actúa como fuente local de lectura, `watch()`
notifica cambios y la capa de sync mantiene una cola persistente para
empujar operaciones cuando vuelve la red.

Casos típicos:

- levantamiento de encuestas en campo;
- inspecciones, visitas y órdenes de trabajo;
- inventarios en bodegas con conectividad intermitente;
- aplicaciones móviles que no pueden perder una captura por un corte de red.

### Clientes REST con contratos tipados

Úsalo cuando el proyecto tiene muchos endpoints y quieres evitar que cada
equipo repita serialización, headers, retries, paginación, manejo de errores y
adaptadores manuales.

El contrato se declara una vez y el builder genera el cliente. Los mismos
modelos pueden reutilizarse en JSON, REST, formularios y SQLite.

### Formularios que deben reflejar el modelo

Úsalo cuando la validación pertenece al contrato del dato y no a un widget
particular. `@Form` genera estados de campo, conversión tipada, validación
síncrona y asíncrona, debounce, errores REST y bindings que pueden conectarse
a controles Flutter existentes.

Esto evita crear un controller distinto para cada `TextField`: el control
conserva su ciclo de vida y el formulario conserva el estado y las reglas.

### Realtime con recuperación controlada

Úsalo cuando el servidor publica cambios por WebSocket o SSE y la aplicación
debe recuperarse de cierres, renovar credenciales, conservar un cursor o
detectar una conexión estancada.

`SseReconnector` y `WebSocketReconnector` exponen estados observables,
backoff, headers dinámicos, recuperación de `401`, tratamiento terminal de
`403`, heartbeats y cancelación segura. El consumidor decide cuándo confirmar
un evento procesado.

### Datos locales consultables con SQLite

Úsalo cuando necesitas consultas tipadas y composables sin construir SQL a
mano en cada pantalla o repositorio. LINQ mantiene la consulta diferida y el
engine SQLite traduce el árbol a SQL cuando se materializa.

El CLI puede ayudar a detectar diferencias de esquema, pero las operaciones
destructivas (`DROP` o modificaciones incompatibles) deben revisarse y
confirmarse mediante una migración explícita.

## Casos de uso de extremo a extremo

### 1. Cliente REST reactivo con invalidación

```dart
@Serializable(copyWith: true, equality: true)
class Account {
  const Account({required this.id, required this.balance});

  final String id;
  final double balance;
}

@Serializable()
class TransferRequest {
  const TransferRequest({required this.sourceId, required this.amount});

  final String sourceId;
  final double amount;
}

@Serializable()
class TransferReceipt {
  const TransferReceipt({required this.id});

  final String id;
}

@RestClient(baseUrl: 'https://api.example.com')
abstract class BankingClient {
  @QueryCache(tags: <String>['account:{id}'])
  @HttpGet('/accounts/{id}')
  Stream<Account> watchAccount(@Path('id') String id);

  @Invalidates(<String>['account:{request.sourceId}'])
  @HttpPost('/transfers')
  Future<TransferReceipt> transfer(@Body() TransferRequest request);
}
```

La primera suscripción inicia la carga. Suscripciones concurrentes comparten
la petición en vuelo; una transferencia exitosa invalida la cuenta relacionada
y provoca una nueva lectura. La cache no conoce Flutter, Bloc ni Riverpod:
ellos solo consumen el `Stream<Account>`.

Para aislar datos por sesión o por cliente:

```dart
final client = BankingClientImpl(
  config: RestClientConfig(queryCache: RestQueryCache()),
);

await dRest.queryCache.clear(); // útil al cerrar sesión si se usa la cache global
```

La cache de instancia es preferible cuando conviven usuarios, tenants o
clientes con ciclos de vida independientes.

### 2. Persistencia SQLite y consultas diferidas

```dart
dRocketSqlite();
initializeD();

final db = await Db.open(path: 'app.db');

final pending = await db
    .set<Task>()
    .where(Expr.lambda(<Expr>[Expr.param('task')], Expr.binary(
      '==',
      Expr.member(Expr.param('task'), 'completed'),
      Expr.const_(false),
    )))
    .orderBy_(Expr.lambda(
      <Expr>[Expr.param('task')],
      Expr.member(Expr.param('task'), 'createdAt'),
    ))
    .toListAsync_();
```

La consulta se compone sin materializar cada paso. El provider SQLite la
traduce al ejecutar `toListAsync_()`. Para cambios que deben reflejarse en la
interfaz, se puede usar la variante `watch()` sobre el mismo conjunto.

### 3. Formulario con cualquier control Flutter

El formulario se genera a partir del modelo; no impone widgets propios:

```dart
@Form()
class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  @Required()
  @Email()
  final String email;

  @Required()
  final String password;
}
```

Uso conceptual con controles existentes:

```dart
final form = LoginRequestForm();

TextField(
  onChanged: form.email.bind,
  decoration: InputDecoration(errorText: form.email.errorText),
);

TextField(
  obscureText: true,
  onChanged: form.password.bind,
  decoration: InputDecoration(errorText: form.password.errorText),
);

final request = form.build();
```

La integración Flutter opcional puede ayudar con el binding, pero el contrato
de formulario vive en Dart. Para una validación remota se usa
`validateAsync()`; mientras corre, el estado es `validating`, y luego pasa a
`valid` o `invalid`. Un `RestHttpException` puede alimentar directamente los
errores de campo mediante `applyRestError(...)`.

### 4. SSE resumible y autenticado

```dart
final reconnector = SseReconnector(
  factory: () => HttpSseClient(),
  url: Uri.parse('https://api.example.com/events'),
  headersProvider: () async => <String, String>{
    'Authorization': 'Bearer ${await tokenStore.accessToken()}',
  },
  onUnauthorized: () => tokenStore.refresh(),
  manualAcknowledge: true,
  inactivityTimeout: const Duration(minutes: 2),
);

final subscription = reconnector.events.listen((event) async {
  await processEvent(event);
  reconnector.acknowledge(event);
});

await reconnector.start();
```

El cursor solo avanza después de procesar el evento. `stop()` cancela la
conexión activa, los reintentos y las suscripciones; `start()` puede volver a
usarse. `dispose()` cierra también los streams públicos.

### 5. Sincronización por cambios de campo

```dart
final change = DeltaSync.diff(
  tableName: 'tasks',
  primaryKey: 'id',
  previous: <String, Object?>{'id': 't-1', 'title': 'Viejo', 'done': false},
  current: <String, Object?>{'id': 't-1', 'title': 'Nuevo', 'done': false},
  version: 7,
);
```

El delta contiene únicamente los campos modificados. Esto reduce el payload
de sincronización y facilita resolver conflictos sin reemplazar una fila
completa.

### 6. Diagnóstico operativo

El runtime publica diagnósticos correlacionados para REST y realtime. La
extensión independiente de Flutter DevTools presenta esos eventos en una
interfaz filtrable por categoría, estado y fecha. La captura de cuerpos y
datos sensibles debe habilitarse de forma explícita.

## Cuándo no es la primera opción

`d_rocket` no pretende ser la solución universal para todos los problemas de
la aplicación. Evalúa otra herramienta o un adaptador si:

- necesitas un framework de UI, routing o manejo de estado;
- tu backend es exclusivamente GraphQL y quieres un cache normalizado basado
  en el esquema GraphQL;
- necesitas CRDT o colaboración distribuida con resolución a nivel de
  operación;
- buscas generación completa desde cualquier especificación OpenAPI sin
  escribir contratos anotados;
- necesitas scheduling nativo de tareas en segundo plano, push notifications
  o almacenamiento seguro de credenciales;
- requieres un motor SQL distinto y todavía no existe un engine compatible
  con tu plataforma.

En esos casos, `d_rocket` puede seguir ocupándose de serialización, REST,
formularios o realtime, mientras otra herramienta cubre la responsabilidad
especializada.

## Mapa rápido de decisión

| Necesidad | Capacidad | Paquetes habituales |
|---|---|---|
| JSON ↔ Dart | Serialización y converters | `d_rocket` + `d_rocket_builder` |
| API tipada | REST, interceptores y resiliencia | `d_rocket` + builder |
| Cache REST reactiva | deduplicación e invalidación por tags | `d_rocket` + builder |
| SQLite offline-first | ORM, LINQ, migraciones y `watch()` | `d_rocket` + builder + `d_rocket_engine_sqlite` |
| Captura de datos | formularios y validación | `d_rocket` + builder; Flutter opcional |
| Eventos en tiempo real | WebSocket/SSE y reconexión | `d_rocket` + builder |
| Push/pull y conflictos | sync y deltas | `d_rocket` + engine persistente |
| Inspección durante desarrollo | eventos de diagnóstico | `d_rocket_devtools_extension` |

## Regla práctica

Empieza por el contrato que ya existe en tu dominio:

1. anota el modelo con `@Serializable()`;
2. añade `@RestClient` si hay API HTTP;
3. añade `@Form` si el mismo modelo se captura desde una pantalla;
4. añade `@Table` y SQLite si el dato debe sobrevivir offline;
5. añade sync o realtime cuando exista una necesidad real de convergencia;
6. ejecuta el codegen y revisa los artefactos generados en CI.

El resultado es incremental: cada capa aporta una capacidad concreta sin
obligar a adoptar el resto.
