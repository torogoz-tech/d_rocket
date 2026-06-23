# Cookbook

Real-world recipes. Each recipe is a self-contained
example you can drop into a project.

---

## Table of contents

- [Authentication — bearer token interceptor](#authentication)
- [Pagination — keyset and offset](#pagination)
- [Multi-tenant schemas](#multi-tenant)
- [Full-text search](#full-text-search)
- [Audit logs — automatic timestamps and changelog](#audit-logs)
- [Time-zone handling](#time-zones)
- [Schema versioning and rolling upgrades](#schema-versioning)
- [Soft delete](#soft-delete)
- [Database encryption (SQLCipher)](#database-encryption)
- [Background sync — `Isolate` worker](#background-sync)
- [Reactive UI from a list view](#reactive-ui)
- [Chat with WebSocket and offline fallback](#chat)
- [Live dashboard with SSE](#live-dashboard)
- [Working with a REST backend that has paginated lists](#rest-pagination)
- [Token refresh — automatic auth](#token-refresh)
- [CSV import / export](#csv)
- [Bulk insert from a JSON file](#bulk-insert)
- [Working with images and BLOBs](#images-blobs)
- [Computed fields in queries](#computed-fields)
- [Database migrations during a long-running transaction](#long-transactions)

---

## Authentication

A typical REST client needs an `Authorization: Bearer <token>`
header on every request. Implement an interceptor:

```dart
class AuthInterceptor implements RestInterceptor {
  AuthInterceptor(this.tokenStore);
  final TokenStore tokenStore;

  @override
  Future<void> onRequest(RestRequest request) async {
    final token = await tokenStore.accessToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
  }
}
```

Register globally:

```dart
dRest.use(AuthInterceptor(tokenStore));
```

For per-client auth, pass the interceptor to the
`RestConfig`:

```dart
final client = dRest.create<ShopClient>(config: RestConfig(
  baseUrl: 'https://api.example.com',
  interceptors: [AuthInterceptor(tokenStore)],
));
```

The `TokenStore` is your abstraction over the secure
storage. On Flutter, use `flutter_secure_storage`:

```dart
class TokenStore {
  final _storage = FlutterSecureStorage();

  Future<String?> accessToken() => _storage.read(key: 'access_token');
  Future<String?> refreshToken() => _storage.read(key: 'refresh_token');

  Future<void> save(String access, String refresh) async {
    await _storage.write(key: 'access_token', value: access);
    await _storage.write(key: 'refresh_token', value: refresh);
  }

  Future<void> clear() => _storage.deleteAll();
}
```

For automatic token refresh on 401, see [Token refresh](#token-refresh).

## Pagination

There are two common pagination strategies. Pick the
one your backend uses.

### Keyset (cursor-based) pagination

Best for stable, large datasets. The server returns
a cursor; the client uses it on the next request:

```dart
@RestClient(baseUrl: 'https://api.example.com')
abstract class OrderClient {
  @HttpGet('/orders')
  Future<OrderPage> listOrders(@Query('after') String? after);
}

@Serializable()
class OrderPage {
  OrderPage({required this.items, required this.nextCursor});
  final List<Order> items;
  final String? nextCursor;
}

// Usage:
String? cursor;
do {
  final page = await client.listOrders(after: cursor);
  for (final order in page.items) {
    db.set<Order>().add(order);
  }
  await db.saveChanges();
  cursor = page.nextCursor;
} while (cursor != null);
```

### Offset-based pagination

Simpler but slower on large datasets:

```dart
@RestClient(baseUrl: 'https://api.example.com')
abstract class OrderClient {
  @HttpGet('/orders')
  Future<List<Order>> listOrders(
    @Query('page') int page,
    @Query('pageSize') int pageSize,
  );
}

// Usage:
const pageSize = 100;
for (var page = 0; ; page++) {
  final orders = await client.listOrders(page, pageSize);
  if (orders.isEmpty) break;
  for (final order in orders) {
    db.set<Order>().add(order);
  }
  await db.saveChanges();
  if (orders.length < pageSize) break;
}
```

For very large imports, do the `saveChanges` per page
(not per item) so the transaction is bounded:

## Multi-tenant schemas

A multi-tenant app has a `tenantId` on every row and a
`tenantId` on every query. Make this explicit with a
helper:

```dart
mixin TenantScoped {
  String get tenantId;
}

@Table('orders')
class Order extends Record with TenantScoped {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column(name: 'tenant_id') @Index() final String tenantId;
  @Column() final double total;

  @override
  final String tenantId;
}
```

The `with TenantScoped` mixin is a marker that
documents the table. The query helper:

```dart
extension TenantSet<T extends Record> on DbSet<T> {
  Queryable<T> forTenant(String tenantId) {
    return where(Expr.lambda(<Expr>[Expr.param('p')],
      Expr.binary('==',
        Expr.member(Expr.param('p'), 'tenantId'),
        Expr.const_(tenantId)),
    ));
  }
}

// Usage:
final myOrders = await db
    .set<Order>()
    .forTenant(currentTenant.id)
    .orderBy_(...)
    .toListAsync_();
```

For schema-level isolation (one db per tenant), use
multiple `Db` instances:

```dart
Future<Db> openForTenant(Tenant tenant) async {
    dRocketSqlite();
return Db.open(path: 'tenants/${tenant.id}.db');
}
```

Each tenant gets its own SQLite file, no cross-tenant
joins possible.

## Full-text search

SQLite has FTS5 for full-text search. The framework
emits a virtual table for any `@Table` annotated
with `@FullTextIndex`:

```dart
@Table('articles')
@FullTextIndex(['title', 'body'], tokenizer: 'porter')
class Article extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final String title;
  @Column() final String body;
  @Column() final DateTime publishedAt;
}
```

The codegen creates an `articles_fts` virtual table
and triggers to keep it in sync. The query helper:

```dart
final hits = await db
    .set<Article>()
    .fullTextSearch_('quantum entanglement',
        orderBy: 'rank',
        limit: 20);
```

The `fullTextSearch_` operator is push-down translated
to:

```sql
SELECT a.* FROM articles a
JOIN articles_fts fts ON a.id = fts.rowid
WHERE articles_fts MATCH 'quantum entanglement'
ORDER BY rank
LIMIT 20;
```

For more complex search (boolean, phrase, NEAR), pass
the raw FTS5 expression:

```dart
final hits = await db
    .set<Article>()
    .rawFts_('title NEAR "quantum" AND body : "entanglement"');
```

## Audit logs

Track who changed what and when. Two patterns: (1) per-
table audit columns, (2) global changelog.

### Per-table audit columns

```dart
@Table('orders')
class Order extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final double total;

  @Column(name: 'created_at', defaultValue: 'CURRENT_TIMESTAMP')
  final DateTime createdAt;

  @Column(name: 'created_by') final String? createdBy;

  @Column(name: 'updated_at')
  final DateTime updatedAt;

  @Column(name: 'updated_by') final String? updatedBy;
}
```

A change-tracker interceptor updates the audit fields
on every save:

```dart
class AuditInterceptor implements RestInterceptor {
  @override
  void onResponse(RestRequest request, RestResponse response) {
    // No-op for the REST layer.
  }

  @override
  Future<void> onRequest(RestRequest request) async {
    // For the ORM: see ChangeTracker hooks below.
  }
}

// On the ORM:
class AuditChangeHook implements ChangeTrackerHook {
  @override
  void onSave(ChangeTracker tracker, Db db) {
    final now = DateTime.now();
    final user = currentUser.id;
    for (final entry in tracker.added) {
      entry.entity.createdAt = now;
      entry.entity.createdBy = user;
      entry.entity.updatedAt = now;
      entry.entity.updatedBy = user;
    }
    for (final entry in tracker.modified) {
      entry.entity.updatedAt = now;
      entry.entity.updatedBy = user;
    }
  }
}
```

### Global changelog

A separate `audit_log` table records every change
with before/after snapshots:

```dart
@Table('audit_log')
class AuditEntry extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final String entityType;
  @Column() final String entityId;
  @Column() final String kind;             // add / update / remove
  @Column(name: 'before_json') final String? beforeJson;
  @Column(name: 'after_json') final String? afterJson;
  @Column(name: 'changed_by') final String? changedBy;
  @Column(name: 'changed_at', defaultValue: 'CURRENT_TIMESTAMP')
  final DateTime changedAt;
}
```

The `AuditChangeHook` populates it on every save.

## Time-zone handling

Store every `DateTime` as UTC. Convert to local time
only at the UI boundary.

```dart
@Table('orders')
class Order extends Record {
  @Column(name: 'placed_at', format: Format.iso8601DateTime)
  final DateTime placedAt;  // always UTC
}
```

`Format.iso8601DateTime` encodes as a UTC ISO-8601
string. On the way in, the framework decodes the
string and stores a UTC `DateTime`. On the way out,
the format produces a UTC ISO-8601 string.

For local-time display, use a helper:

```dart
String formatLocal(DateTime utc) {
  return utc.toLocal().toIso8601String();
}
```

For "yesterday at 3pm"-style formatting, use the
`intl` package.

## Schema versioning and rolling upgrades

When you have multiple app versions in the field
(e.g. a mobile app on v1.0 and v1.1 simultaneously),
the migration runner handles each version's path:

```dart
// v1.0 has migrations 1-4.
// v1.1 adds migration 5.

MigrationStrategy(
  version: 5,  // the latest
  migrations: [M001(), M002(), M003(), M004(), M005()],
);
```

A user on v1.0 (db at v4) opening the v1.1 app
triggers the upgrade to v5 (just M005). A user on
v1.1 (db at v5) is a no-op.

If v1.2 makes a breaking change to migration 5, the
runner detects the checksum mismatch and refuses to
proceed. The recommended fix is to add a new
migration 6 that undoes the breaking change and
applies the new shape.

## Soft delete

Mark rows as deleted without actually removing them.
Useful for "trash" features and audit requirements:

```dart
@Table('orders')
class Order extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final double total;

  @Column(name: 'deleted_at') final DateTime? deletedAt;
}

// A `softDelete` operator:
extension SoftDeleteOps<T extends Record> on DbSet<T> {
  Future<int> softDeleteWhere_(Expr<T, bool> predicate) async {
    final now = DateTime.now();
    // ... apply update ...
  }
}
```

By convention, every query excludes soft-deleted rows
by default. Add a filter at the top of every chain:

```dart
final visibleOrders = await db
    .set<Order>()
    .where(Expr.lambda(<Expr>[Expr.param('o')],
      Expr.binary('==',
        Expr.member(Expr.param('o'), 'deletedAt'),
        Expr.const_(null)),
    ))
    .orderBy_(...)
    .toListAsync_();
```

Or use a global filter on the `Db`:

```dart
db.setGlobalFilter(Expr.lambda(<Expr>[Expr.param('o')],
  Expr.binary('==',
    Expr.member(Expr.param('o'), 'deletedAt'),
    Expr.const_(null)),
));
```

## Database encryption (SQLCipher)

`d_rocket` opens an encrypted database with a
`password` parameter on `Db.open` (or
`Db.inMemory`). The password is forwarded to the
SQLite engine as `PRAGMA key`, with single quotes
escaped and a verification query that surfaces
wrong-password errors at open time.

```dart
final key = await keyStore.readKey(); // flutter_secure_storage
dRocketSqlite();
final db = await Db.open(
  path: 'app.db',
  password: key,
);
```

The `keyStore` is your abstraction over the platform's
secure storage (Keychain on iOS, Keystore on Android,
DPAPI on Windows, libsecret on Linux). The key is
read on every open and held in memory for the
duration of the connection; `d_rocket` does not
persist it.

> The `password` parameter is a no-op unless the
> consumer bundles a SQLCipher build of the native
> library. On Flutter, swap `sqlite3_flutter_libs`
> for `sqlcipher_flutter_libs`. On desktop, install
> `libsqlcipher` system-wide. See the
> [Security — encrypted databases](13-faq.md#how-do-i-open-an-encrypted-database)
> section of the FAQ for the full setup.

To change the password of an existing database, see
[the `PRAGMA rekey` recipe in the FAQ](13-faq.md#can-i-change-the-password-of-an-existing-database).
For a key rotation strategy, see
[Schema versioning and rolling upgrades](#schema-versioning).

## Background sync — `Isolate` worker

For a long-running sync, run the push / pull loop in
a Dart `Isolate` so the main UI stays responsive:

```dart
import 'dart:isolate';

void main() {
  Isolate.spawn(_syncEntryPoint, SendPort(...));
}

void _syncEntryPoint(SendPort mainPort) {
  // Open a db in this isolate.
  final db = Db.openSync(path: 'app.db');
  final sync = MyBackendSyncProvider(...);
  sync.attach(db);

  // Run the push loop forever.
  sync.runForever();
}
```

The framework's `IsolateWorker` helper handles the
port plumbing and the lifecycle:

```dart
final worker = IsolateWorker<Db>(
  spawn: (sendPort) => Db.openSync(path: 'app.db'),
  onMessage: (db, message) { /* ... */ },
);

await worker.start();
```

For Flutter, use `compute(...)` for one-off tasks and
the isolate worker for long-running pipelines.

## Reactive UI from a list view

Wire a `DbSet<T>.watch()` to a `StreamBuilder`:

```dart
class OrderListView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Order>>(
      stream: db.set<Order>().watch(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snapshot.data!;
        return ListView.builder(
          itemCount: orders.length,
          itemBuilder: (context, i) {
            return OrderTile(order: orders[i]);
          },
        );
      },
    );
  }
}
```

The `watch()` stream re-emits on every change. The
framework's debouncing (default 16ms) keeps the UI
smooth even on batch updates.

For per-row updates without a full list rebuild, use
a finer-grained stream:

```dart
StreamBuilder<Order?>(
  stream: db.set<Order>().where(...).watchOne(),
  // ...
);
```

## Chat with WebSocket and offline fallback

Wire a WebSocket as the primary channel, fall back to
REST polling when offline:

```dart
class ChatClient {
  ChatClient(this.realtime, this.rest);

  final RealtimeClient realtime;
  final ChatRestClient rest;

  Stream<Message> incoming() {
    return realtime.messages();
  }

  Future<void> send(Message msg) async {
    try {
      await realtime.send(msg);
    } on NetworkException {
      // Fall back to REST with a sync op.
      await rest.post(msg);
    }
  }
}
```

The `realtime.messages()` is the WebSocket stream
(Layer 6). The `rest.post` is a REST call (Layer 2)
that enqueues a sync op (Layer 5). When the WebSocket
reconnects, the queued ops are pushed and the local
DB is updated.

## Live dashboard with SSE

For a one-way server-push (e.g. metrics, alerts), use
SSE:

```dart
@SseRoute(url: 'https://api.example.com/metrics')
abstract class MetricsClient {
  @SseStream('/cpu')
  Stream<CpuMetric> cpu();
}

final client = dRealtime.create<MetricsClient>(config: ...);

client.cpu().listen((metric) {
  print('cpu: ${metric.value}%');
});
```

The stream re-emits every time the server pushes a new
metric. For long-lived connections, the framework's
auto-reconnect keeps the stream alive across network
blips.

## Working with a REST backend that has paginated lists

The framework's `DbSet<T>.addAll` is a good fit for
batch imports from a paginated REST endpoint. The
loop:

```dart
String? cursor;
do {
  final page = await client.listProducts(after: cursor);
  db.set<Product>().addAll(page.items);
  await db.saveChanges();
  cursor = page.nextCursor;
} while (cursor != null);
```

For very large imports, do the `saveChanges` per page
(not per item) so the transaction is bounded:

```dart
do {
  final page = await client.listProducts(after: cursor);
  db.set<Product>().addAll(page.items);
  await db.saveChanges();  // 100 rows per transaction
  cursor = page.nextCursor;
} while (cursor != null);
```

## Token refresh — automatic auth

A common need: when the access token expires (the
server returns 401), automatically refresh it and
retry the request. The pattern is an interceptor:

```dart
class TokenRefreshInterceptor implements RestInterceptor {
  TokenRefreshInterceptor(this.tokenStore, this.refreshClient);
  final TokenStore tokenStore;
  final RefreshClient refreshClient;

  @override
  Future<void> onRequest(RestRequest request) async {
    final token = await tokenStore.accessToken();
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }
  }

  @override
  Future<RestResponse?> onResponse(
    RestRequest request,
    RestResponse response,
  ) async {
    if (response.status != 401) return null;
    // Try to refresh the token.
    final newToken = await refreshClient.refresh();
    if (newToken == null) return null;
    // Save the new token.
    await tokenStore.saveAccess(newToken);
    // Retry the original request.
    return request.send(retry: true);
  }
}
```

The `retry: true` parameter tells the framework to
resend the request with the new token. The interceptor
chain handles the retry transparently.

## CSV import / export

The framework doesn't ship a CSV reader, but the LINQ
provider makes export trivial:

```dart
Future<File> exportOrdersToCsv(Db db) async {
  final orders = await db
      .set<Order>()
      .orderBy_(Expr.lambda(<Expr>[Expr.param('o')],
        Expr.member(Expr.param('o'), 'placedAt')))
      .toListAsync_();

  final buffer = StringBuffer();
  buffer.writeln('id,total,status,placedAt');
  for (final o in orders) {
    buffer.writeln('${o.id},${o.total},${o.status},${o.placedAt}');
  }
  return File('orders.csv').writeAsString(buffer.toString());
}
```

For import, use the `package:csv` package and the
same `DbSet<T>.add` API.

## Bulk insert from a JSON file

```dart
final raw = await File('orders.json').readAsString();
final list = (json.decode(raw) as List).cast<Map<String, Object?>>();
final orders = list.map(Order.fromJson).toList();

db.set<Order>().addAll(orders);
await db.saveChanges();
```

For very large files, stream the JSON:

```dart
final stream = File('orders.json').openRead()
    .transform(utf8.decoder)
    .transform(json.decoder)
    .expand((event) => event as List);

const batchSize = 1000;
final batch = <Order>[];
await for (final raw in stream) {
  batch.add(Order.fromJson(raw as Map<String, Object?>));
  if (batch.length >= batchSize) {
    db.set<Order>().addAll(batch);
    await db.saveChanges();
    batch.clear();
  }
}
if (batch.isNotEmpty) {
  db.set<Order>().addAll(batch);
  await db.saveChanges();
}
```

## Working with images and BLOBs

Store images in a separate table, referenced by the
parent row:

```dart
@Table('avatars')
class Avatar extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column(name: 'user_id') @Unique() final int userId;
  @Column() final Uint8List data;
  @Column() final String contentType;
}
```

Storing BLOBs in the same row as a `User` is fine for
small images (< 100KB), but for larger media, use a
separate table or store on disk and reference by path.

For lazy loading, use a separate query:

```dart
final avatar = await db
    .set<Avatar>()
    .firstOrDefaultAsync_(Expr.lambda(<Expr>[Expr.param('a')],
      Expr.binary('==',
        Expr.member(Expr.param('a'), 'userId'),
        Expr.const_(userId))));
```

## Computed fields in queries

SQLite supports computed columns with `GENERATED ALWAYS AS`:

```dart
@Table('orders')
class Order extends Record {
  @PrimaryKey(autoIncrement: true) final int id;
  @Column() final double subtotal;
  @Column() final double tax;
  @Column(generated: 'subtotal * (1 + tax)', stored: true)
  final double total;
}
```

For runtime computations (not stored in the DB), use
a `select_` in the query:

```dart
final orderWithTotal = await db
    .set<Order>()
    .select_(Expr.lambda(<Expr>[Expr.param('o')],
      Expr.anon({
        'id': Expr.member(Expr.param('o'), 'id'),
        'total': Expr.binary('*',
          Expr.member(Expr.param('o'), 'subtotal'),
          Expr.binary('+', Expr.const_(1), Expr.member(Expr.param('o'), 'tax'))),
      }),
    ))
    .firstAsync_();
```

## Database migrations during a long-running transaction

For migrations that touch large tables, the default
"all-or-nothing" transaction can lock the database
for too long. The framework's `MigrationStrategy`
supports a "split" mode:

```dart
MigrationStrategy(
  version: 5,
  migrations: [M001(), M002(), M003(), M004(), M005()],
  longRunningMigrationThreshold: Duration(seconds: 30),
  longRunningMigrationPolicy: LongRunningMigrationPolicy.splitPerRow,
);
```

The `splitPerRow` policy re-batches the migration into
per-row updates, so each transaction touches only N
rows. The full migration is still atomic in the
sense that a crash mid-way can be re-run, but the
database is never locked for more than a few seconds.

This is an advanced pattern; use it only when
`migration doctor` warns about long-running
migrations.
