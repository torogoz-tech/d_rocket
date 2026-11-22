# d_rocket 2.6.0 Reactive REST Cache and Value Models

## Goal

Extend the data layer for network-first applications with a reactive in-memory
REST query cache and opt-in generated value-model helpers, without adding a
dependency on Flutter, Bloc, Riverpod or any other presentation framework.

## Scope

### Reactive REST queries

Add two method annotations:

```dart
@QueryCache(
  tags: <String>['account:{id}'],
  staleTime: Duration(seconds: 30),
)
Stream<Account> watchAccount(@Path('id') String id);

@Invalidates(<String>['account:{request.sourceAccountId}', 'recent_movements'])
Future<TransferReceipt> executeTransfer(@Body() TransferRequest request);
```

The generated client must use an instance-scoped `RestQueryCache` that:

- deduplicates concurrent requests for the same normalized GET key;
- retains successful values for a configurable stale/cache lifetime;
- exposes a `Stream<T>` for active subscribers;
- refetches active queries after a successful mutation invalidates a matching tag;
- supports path, query, header and body-property tag placeholders without
  evaluating arbitrary code;
- clears values, registrations and pending cache work through
  `dRest.clearQueryCache()` / the cache instance;
- never includes credentials in keys or diagnostic events;
- propagates HTTP and conversion errors to the query stream;
- does not poll, own UI state, or introduce Flutter dependencies.

Invalidation runs only after the annotated mutation returns successfully.
Failed mutations do not invalidate cached data. `clear()` advances a cache
generation so a late response cannot repopulate data after logout.

### Generated value-model helpers

Extend `@Serializable` with additive opt-in flags:

```dart
@Serializable(copyWith: true, equality: true)
class Account {
  const Account({required this.id, required this.balance});

  final String id;
  final double balance;
}
```

`copyWith: true` emits a typed extension using a private sentinel so nullable
fields can distinguish “keep the current value” from “set null”.

Because a Dart builder cannot reopen an existing class and inject `==` or
`hashCode`, `equality: true` emits a generated mixin and requires the model to
opt into it explicitly:

```dart
class Account with _$AccountEquality { ... }
```

The builder must produce a clear generation error when the flag is enabled but
the generated mixin is not applied. Equality uses all declared serializable
fields and a deterministic deep comparison/hash for lists, sets and maps.
No equality or copyWith code is emitted by default.

## Non-goals

- No Flutter widgets or Bloc/Riverpod adapters.
- No background scheduler; platform scheduling remains a host/mobile concern.
- No Socket.IO, GraphQL or arbitrary server cache protocol in this release.
- No mutation of user source files or generated files committed manually.
- No automatic equality injection that Dart's part-file model cannot support.

## Compatibility

- Dart 3.11.5, 3.12 and 3.13.
- Existing `HttpCache`, `RestClient`, serializer and generated clients remain
  source-compatible when the new annotations/options are absent.
- No new runtime package dependency is required.
