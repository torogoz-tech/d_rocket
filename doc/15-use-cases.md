# Why use d_rocket?

`d_rocket` is a data layer for Dart and Flutter applications that need to
keep models, JSON, transport, local persistence, synchronization and realtime
events consistent.

You do not need to adopt the entire framework. Adoption is capability-based:
start with serialization and REST, add forms later, and enable SQLite or
synchronization only when the product needs them.

## Where it fits especially well

### Offline-first applications

Use d_rocket when the application must keep reading and capturing data while
connectivity is unstable. SQLite can be the local read source, `watch()` emits
changes, and sync keeps a persistent queue for operations that must be sent
when the network returns.

Typical examples include field surveys, inspections, work orders, warehouse
inventory and mobile applications that cannot lose a capture because of a
network outage.

### Typed REST clients

Use d_rocket when many endpoints would otherwise make every team repeat JSON
serialization, headers, retries, pagination and error handling. Declare the
contract once and let the builder generate the client. The same models can be
reused across JSON, REST, forms and SQLite.

### Model-driven forms

Use d_rocket when validation belongs to the data contract rather than to a
specific widget. `@Form` generates field state, typed conversion,
synchronous/asynchronous validation, debounce, REST errors and bindings that
connect to existing Flutter controls.

This avoids creating a controller for every `TextField`: the control keeps
its lifecycle while the form owns state and validation rules.

### Resilient realtime

Use d_rocket when a server publishes WebSocket or SSE events and the client
must recover from disconnects, renew credentials, preserve a cursor or detect
an idle connection. `SseReconnector` and `WebSocketReconnector` expose
observable states, backoff, dynamic headers, `401` recovery, terminal `403`
handling, heartbeats and safe cancellation.

### Typed SQLite queries

Use d_rocket when you need composable queries without rebuilding SQL in every
screen or repository. LINQ remains deferred and the SQLite engine translates
the expression tree when the query is materialized.

The migration CLI can identify schema differences, but destructive operations
such as `DROP` or incompatible modifications must be reviewed and confirmed
with an explicit migration.

## End-to-end examples

### 1. Reactive REST with tag invalidation

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

Concurrent subscribers share the in-flight request. A successful transfer
invalidates the related account and triggers a fresh read. The cache does not
depend on Flutter, Bloc or Riverpod; those layers consume the stream.

Use an instance-scoped cache when sessions, tenants or clients have separate
lifecycle boundaries:

```dart
final client = BankingClientImpl(
  config: RestClientConfig(queryCache: RestQueryCache()),
);

await dRest.queryCache.clear(); // clear global data during logout
```

### 2. SQLite and deferred queries

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

The query is composed without materializing every step. The SQLite provider
translates it when `toListAsync_()` executes. Use `watch()` when the UI needs
to observe changes to the same set.

### 3. A form with any Flutter control

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

```dart
final form = LoginRequestForm();

TextField(
  onChanged: form.email.bind,
  decoration: InputDecoration(errorText: form.email.errorText),
);

final request = form.build();
```

The optional Flutter adapter can assist with binding, but the form contract
lives in Dart. Remote validation uses `validateAsync()` and exposes
`validating`, `valid` and `invalid`. A `RestHttpException` can be applied with
`form.applyRestError(error)`.

### 4. Resumable authenticated SSE

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

The cursor advances only after processing the event. `stop()` cancels the
active connection, retries and subscriptions; `start()` can be called again.
`dispose()` also closes the public streams.

### 5. Field-level synchronization

```dart
final change = DeltaSync.diff(
  tableName: 'tasks',
  primaryKey: 'id',
  previous: <String, Object?>{'id': 't-1', 'title': 'Old', 'done': false},
  current: <String, Object?>{'id': 't-1', 'title': 'New', 'done': false},
  version: 7,
);
```

The delta contains only changed fields. This reduces synchronization payloads
and makes conflict resolution possible without replacing a complete row.

### 6. Development diagnostics

The runtime publishes correlated REST and realtime diagnostics. The separate
Flutter DevTools extension displays those events with filtering by category,
state and timestamp. Body and sensitive-data capture must be enabled
explicitly.

## When it is not the first choice

Consider a specialized tool or adapter when:

- you need a UI framework, routing or state management;
- your backend is exclusively GraphQL and requires a schema-normalized cache;
- you need CRDTs or distributed collaboration with operation-level merging;
- you want complete client generation from arbitrary OpenAPI without writing
  annotated contracts;
- you need native background scheduling, push notifications or secure
  credential storage;
- you require a SQL engine without a compatible d_rocket adapter.

d_rocket can still own serialization, REST, forms or realtime while another
tool covers the specialized responsibility.

## Quick decision map

| Need | Capability | Typical packages |
|---|---|---|
| JSON ↔ Dart | Serialization and converters | `d_rocket` + `d_rocket_builder` |
| Typed API | REST, interceptors and resilience | `d_rocket` + builder |
| Reactive REST cache | Deduplication and tag invalidation | `d_rocket` + builder |
| SQLite offline-first | ORM, LINQ, migrations and `watch()` | `d_rocket` + builder + SQLite engine |
| Data capture | Forms and validation | `d_rocket` + builder; Flutter optional |
| Realtime events | WebSocket/SSE and reconnection | `d_rocket` + builder |
| Push/pull and conflicts | Sync and deltas | `d_rocket` + persistent engine |
| Development inspection | Diagnostic events | `d_rocket_devtools_extension` |

## Practical adoption rule

1. Annotate the domain model with `@Serializable()`.
2. Add `@RestClient` when an HTTP API is involved.
3. Add `@Form` when the same model is captured from a screen.
4. Add `@Table` and SQLite when the data must survive offline.
5. Add sync or realtime when convergence is a real requirement.
6. Run code generation and validate generated artifacts in CI.

Each layer adds one concrete capability without forcing adoption of the rest.
