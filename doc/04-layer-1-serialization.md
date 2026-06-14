# Layer 1 — Serialization

`@Serializable` marks a class as JSON-aware. The
codegen (`d_rocket_builder`) reads the annotation and
emits a `fromJson` constructor, a `toJson` method,
and a registration call into the central
[`Serializer`](https://github.com/torogoz-tech/d_rocket/blob/main/packages/d_rocket/lib/src/serializer/serializer.dart)
registry. The `@SerializableUnion` annotation
turns a sealed class into a discriminated-union
deserializer.

This is the **foundation layer**: every other layer
that handles JSON (REST, sync, realtime) reuses the
same serializers that `@Serializable` registers.

---

## Table of contents

- [Basic usage](#basic-usage)
- [The `Serializer` registry](#the-serializer-registry)
- [`@Serializable` parameters](#serializable-parameters)
- [Field naming — `JsonNaming`](#field-naming)
- [Per-field overrides — `@JsonKey`](#per-field-overrides)
- [Polymorphism and sealed unions](#polymorphism-and-sealed-unions)
- [`UnknownKeyPolicy`](#unknownkeypolicy)
- [Custom encoders — `Format`](#custom-encoders)
- [Polymorphic `fromJson` — `Serializer.fromJson<T>`](#polymorphic-fromjson)
- [API reference](#api-reference)

---

## Basic usage

Mark a class with `@Serializable` and the codegen does
the rest:

```dart
@Serializable()
class Customer {
  Customer({required this.id, required this.name, required this.email});
  final int id;
  final String name;
  final String email;
}
```

After running the codegen (`dart run build_runner
build`), the class gains:

- a `Customer.fromJson(Map<String, dynamic> json)`
  named factory;
- a `Map<String, dynamic> toJson()` method;
- a `CustomerSchema` constant consumed by other
  layers;
- a `registerCustomerSerializer()` call in
  `d_rocket_registry.g.dart` that wires the customer
  into the central registry.

You can then serialize and deserialize:

```dart
final alice = Customer(id: 1, name: 'Alice', email: 'alice@example.com');

final Map<String, dynamic> wire = alice.toJson();
final Customer back = Customer.fromJson(wire);
final String text = Serializer.toJson(alice);
final Customer parsed = Serializer.fromJson<Customer>(text);
```

The generated `fromJson` is **lenient** by default
(unknown keys are silently dropped) — see
[`UnknownKeyPolicy`](#unknownkeypolicy).

## The `Serializer` registry

The framework maintains a singleton `Serializer`
registry that maps `Type` to a `fromJson` /
`toJson` pair. It's the keystone that lets
`Serializer.fromJson<T>(json)` work and that lets
the REST, sync, and realtime layers transparently
deserialize their payloads.

You don't construct the registry by hand —
`initializeD()` (the central generated function)
populates it from every `@Serializable` and
`@SerializableUnion` in the project:

```dart
void initializeD() {
  registerCustomerSerializer();
  registerOrderSerializer();
  registerPaymentUnionSerializer();
  // ... one call per annotated class
}
```

After `initializeD()` runs (once, at app startup),
you can do:

```dart
final Customer? c = Serializer.fromJson<Customer>(rawJsonString);
final Customer c2 = Serializer.fromDynamic<Customer>(decodedMap);
final String s = Serializer.toJson(alice);
final List<Customer> list = Serializer.fromJson<List<Customer>>(rawJsonList);
```

The registry is the only place where the framework
"knows" how to deserialize a type. If `initializeD()`
hasn't been called, the registry is empty and
`Serializer.fromJson` throws.

### Built-in value codecs

`Serializer` ships with built-in codecs for these
runtime types, tried in order before any registered
factory:

- `null` (passthrough)
- Primitives: `int`, `double`, `num`, `bool`, `String`
- `DateTime` (ISO-8601 string)
- `Uri`
- `BigInt`
- `Duration` (microseconds)
- `Enum` (by name)
- `List` / `Set` (element-wise)
- `Map<String, dynamic>` (passthrough)

This means a `@Serializable` class can contain
`DateTime`, `Uri`, etc. fields without an explicit
`@JsonKey(format: ...)` — the framework knows how
to round-trip them.

### Manual registration (no codegen)

If you don't want to use the codegen for a particular
class, you can register a serializer by hand:

```dart
Serializer.register<MyType>(
  fromJson: (Map<String, dynamic> json) => MyType.fromJson(json),
  toJson: (MyType value) => value.toJson(),
);
```

For sealed unions:

```dart
Serializer.registerUnion<PaymentMethod>(
  typeField: 'type',
  discriminator: 'card',
  fromJson: (Map<String, dynamic> json) => CardPayment.fromJson(json),
);
```

This is useful for class hierarchies that the codegen
can't process (e.g. types from third-party packages).

### Snapshot and reset

For debugging and tests:

```dart
final snap = Serializer.snapshot();
print('Registered: ${snap.factories.length} factories');

Serializer.reset();  // clears all registered types
```

## `@Serializable` parameters

```dart
const Serializable({
  this.rename,
  this.discriminator,
  this.typeField,
  this.unknownKeyPolicy = UnknownKeyPolicy.ignore,
  this.naming = JsonNaming.none,
});
```

| Parameter | Default | Purpose |
|---|---|---|
| `rename` | `null` | Optional alias used as a discriminator fallback. |
| `discriminator` | `null` | Explicit discriminator value used for polymorphic payloads. Set on the **case** class (subclass) inside a `@SerializableUnion` to mark which discriminator value routes to that case. |
| `typeField` | `null` | JSON field name used to store/read the discriminator. When set on the case class, overrides the parent's `typeField` for that case. |
| `unknownKeyPolicy` | `UnknownKeyPolicy.ignore` | Behavior on unknown keys. See [`UnknownKeyPolicy`](#unknownkeypolicy). |
| `naming` | `JsonNaming.none` | Global naming strategy for the fields in this class. See [Field naming](#field-naming). |

The **constructor** itself is `const` so the
annotation has no runtime cost — it's pure metadata
for the codegen.

## Field naming

By default, wire keys match Dart field names exactly.
When your backend uses a different convention, use
`JsonNaming` to bridge the gap.

```dart
@Serializable(naming: JsonNaming.snakeCase)
class Product {
  final String productName;     // <-> product_name on the wire
  final double unitPriceUsd;    // <-> unit_price_usd
  final bool inStock;           // <-> in_stock
}
```

Supported values:

| Policy | Effect |
|---|---|
| `JsonNaming.none` | No transformation. Wire key == field name. (Default) |
| `JsonNaming.snakeCase` | `productName` ↔ `product_name` |
| `JsonNaming.camelCase` | `product_name` ↔ `productName`. `UserProfile` → `userProfile` (lowered leading capital). |
| `JsonNaming.kebabCase` | `productName` ↔ `product-name` |
| `JsonNaming.pascalCase` | `productName` → `UserProfile`. `product_name` → `ProductName` (capitalizes the first letter, removes separators). |

For one-off overrides that don't follow the global
policy, use `@JsonKey(name: ...)` per field.

## Per-field overrides

For fields that need a custom wire key, a custom
encoder/decoder, or special-case treatment:

```dart
@Serializable()
class ApiResponse {
  @JsonKey(name: 'http_status_code')
  final int statusCode;

  @JsonKey(ignore: true)
  final String internalNotes;  // not serialised

  @JsonKey(requiredKey: true)
  final String requestId;       // throw if missing or null

  @JsonKey(defaultValue: 'pending')
  final String status;          // fallback when missing

  @JsonKey(converter: 'color')
  final String? backgroundColor;  // looks up ColorToJson / ColorFromJson

  @JsonKey(useEnumIndex: true)
  final Status state;           // encoded as 0/1 instead of "pending"

  @JsonKey(unknownEnumValue: 'pending')
  final Status fallback;        // use "pending" if input is unknown
}
```

`@JsonKey` parameters (from the source):

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `name` | `String?` | `null` | Override the wire key. |
| `ignore` | `bool` | `false` | Exclude this field from both `toJson` and `fromJson`. |
| `defaultValue` | `dynamic` | (none) | Fallback used when the input key is missing or null. |
| `converter` | `String?` | `null` | Prefix for the top-level converter functions the codegen looks for: `XToJson` and `XFromJson`. With `converter: 'color'`, the codegen uses `ColorToJson` and `ColorFromJson`. |
| `useEnumIndex` | `bool` | `false` | For enum fields: encode as the index (0, 1, 2, …) instead of the `name` string. |
| `requiredKey` | `bool` | `false` | Throw if the input key is missing or null during deserialisation. |
| `unknownEnumValue` | `String?` | `null` | For enum fields: the value name to use when an unknown input is received. Defaults to throwing. |

## Polymorphism and sealed unions

For sum types, use `@SerializableUnion` on the
abstract / sealed class and `@Serializable(discriminator: '...')`
on each case.

```dart
@SerializableUnion(typeField: 'type')
sealed class PaymentMethod {}

// Each case:
@Serializable(discriminator: 'card')
class CardPayment extends PaymentMethod {
  CardPayment({required this.last4, required this.brand});
  final String last4;
  final String brand;
}

@Serializable(discriminator: 'bank')
class BankTransfer extends PaymentMethod {
  BankTransfer({required this.accountNumber});
  final String accountNumber;
}
```

The codegen emits a dispatcher that reads the
discriminator value at the configured `typeField`
(here `'type'`) and routes to the right case.

`@SerializableUnion` parameters:

| Parameter | Default | Purpose |
|---|---|---|
| `typeField` | `'type'` | JSON field name that stores the discriminator value. |

Per-case, the `@Serializable(discriminator: '...')`
on the subclass specifies which value routes to this
case. The discriminator value must be unique across
the union's cases.

> **Note**: there is no separate `@SerializableUnionCase`
> annotation. The case marker is `@Serializable(discriminator: '...')`
> on the subclass itself.

## `UnknownKeyPolicy`

`@Serializable` accepts an `unknownKeyPolicy`
parameter that controls the behavior when `fromJson`
sees a key in the input that doesn't map to a Dart
field. Three policies are available:

| Policy | Behavior |
|---|---|
| `UnknownKeyPolicy.ignore` (default) | Silently drops unknown keys. |
| `UnknownKeyPolicy.strict` | Throws `ArgumentError`. |
| `UnknownKeyPolicy.capture` | Captures unknown keys into a `Map<String, Object?> extra` field. The class must declare a field named `extra` of type `Map<String, Object?>` (or nullable) — the codegen fails the build if the field is missing. |

```dart
// Default: drop extras silently.
@Serializable()
class Customer {
  final int id;
  final String name;
}

// Throw on extras.
@Serializable(unknownKeyPolicy: UnknownKeyPolicy.strict)
class StrictCustomer {
  final int id;
  final String name;
}

// Capture extras into `extra`.
@Serializable(unknownKeyPolicy: UnknownKeyPolicy.capture)
class FlexibleCustomer {
  FlexibleCustomer({required this.id, required this.name, this.extra});
  final int id;
  final String name;
  final Map<String, Object?>? extra;
}
```

### Why is the default `ignore` (not `strict`)?

The default was changed from `strict` to `ignore` in
the pre-1.0 release to preserve backwards
compatibility with consumers that had adopted the
old `strict: true` boolean opt-in. The migration
guide in
[CHANGELOG.md](../CHANGELOG.md) documents the
change.

For new code, `strict` is the safer default — it
surfaces payload-shape mismatches early instead of
silently dropping data. The intent of the framework
is to **not lose data**; the default reflects the
least-surprising behavior for migrating users.

## Custom encoders — `Format`

`Format` is a small **class** (not an enum) that
describes per-field encoders. The codegen reads the
`Format` and emits the appropriate encoder / decoder
logic at the call site.

```dart
class Order {
  @JsonKey(format: Format.date('yyyy-MM-dd'))
  final DateTime placedAt;

  @JsonKey(format: Format.trim())
  final String notes;

  @JsonKey(format: Format.custom('color'))
  final String backgroundColor;
}
```

Available constructors:

| Constructor | Wire form | Example |
|---|---|---|
| `Format.trim()` | Whitespace trimmed | `'  hello '` → `'hello'` |
| `Format.uppercase()` | Uppercased | `'pending'` → `'PENDING'` |
| `Format.lowercase()` | Lowercased | `'PENDING'` → `'pending'` |
| `Format.date(pattern)` | `Serializer.formatDate(value, pattern)`. Supported patterns: `'yyyy-MM-dd'`, `'iso8601'`. | `2026-06-12` |
| `Format.custom(name)` | Codegen looks for `XToJson` and `XFromJson` static functions in the same file. | depends on the converters |
| `Format.customWith(formatterType)` | Codegen uses the runtime type `formatterType` to look up the converters. | depends on the converters |

For most use cases the built-in primitives are
enough. For anything else, write a custom converter
pair as top-level functions in the same file:

```dart
@Serializable()
class Theme {
  @JsonKey(format: Format.custom('color'))
  final Color? background;
}

class Color {
  Color(this.r, this.g, this.b);
  final int r, g, b;
}

Map<String, dynamic> ColorToJson(Color c) => {
  'r': c.r, 'g': c.g, 'b': c.b,
};

Color ColorFromJson(Map<String, dynamic> json) => Color(
  json['r'] as int, json['g'] as int, json['b'] as int,
);
```

The codegen emits a call to `ColorToJson(c)` in
`toJson` and a call to `ColorFromJson(json)` in
`fromJson`.

## Polymorphic `fromJson`

`Serializer.fromJson<T>(json)` takes a JSON **string**
and returns a `T`. The dispatch is on the runtime
type of `T`:

```dart
final Customer c = Serializer.fromJson<Customer>(rawJsonString);
final List<Customer> list = Serializer.fromJson<List<Customer>>(rawJsonList);
```

For an already-decoded value (a `Map` or a `List`),
use `Serializer.fromDynamic<T>(decoded)`:

```dart
final Customer c = Serializer.fromDynamic<Customer>(decodedMap);
```

The REST layer uses both internally: when a
`@HttpGet` method returns `Future<List<Customer>>`,
the response body is decoded as a JSON list and each
element is fed through `Serializer.fromJson<Customer>`.

For unions, the dispatch is on the discriminator
field configured via `@SerializableUnion(typeField: ...)`:

```dart
final PaymentMethod p = Serializer.fromJson<PaymentMethod>(paymentJson);
```

The `Serializer` registry holds the dispatcher
function for the abstract type. The codegen emits
it.

## API reference

### `@Serializable(...)`

Class annotation. Parameters:

| Parameter | Default | Purpose |
|---|---|---|
| `rename` | `null` | Optional alias used as a discriminator fallback. |
| `discriminator` | `null` | Discriminator value for a union case. Set on the case class. |
| `typeField` | `null` | JSON field name for the discriminator. Overrides the parent's `typeField`. |
| `unknownKeyPolicy` | `UnknownKeyPolicy.ignore` | Behavior on unknown keys. |
| `naming` | `JsonNaming.none` | Global naming strategy. |

### `@SerializableUnion(...)`

Abstract / sealed class annotation. Parameters:

| Parameter | Default | Purpose |
|---|---|---|
| `typeField` | `'type'` | JSON field name for the discriminator value. |

### `@JsonKey(...)`

Field annotation. Parameters:

| Parameter | Type | Default | Purpose |
|---|---|---|---|
| `name` | `String?` | `null` | Override the wire key. |
| `ignore` | `bool` | `false` | Exclude from serialisation. |
| `defaultValue` | `dynamic` | (none) | Fallback when the key is missing or null. |
| `converter` | `String?` | `null` | Prefix for the converter functions the codegen looks up. |
| `useEnumIndex` | `bool` | `false` | Encode enums as index instead of name. |
| `requiredKey` | `bool` | `false` | Throw if the key is missing or null. |
| `unknownEnumValue` | `String?` | `null` | Fallback value name for unknown enum input. |

### `JsonNaming`

Enum with 5 values:

- `JsonNaming.none`
- `JsonNaming.snakeCase`
- `JsonNaming.camelCase`
- `JsonNaming.kebabCase`
- `JsonNaming.pascalCase`

### `UnknownKeyPolicy`

Enum with 3 values:

- `UnknownKeyPolicy.ignore` (default) — drop unknown
  keys silently.
- `UnknownKeyPolicy.strict` — throw on unknown keys.
- `UnknownKeyPolicy.capture` — capture into the
  `extra` field (the class must declare one).

### `Format`

Class (not enum). Constructors:

- `Format.trim()`
- `Format.uppercase()`
- `Format.lowercase()`
- `Format.date(pattern)` — pattern is `'yyyy-MM-dd'`
  or `'iso8601'`.
- `Format.custom(name)` — looks up `XToJson` /
  `XFromJson`.
- `Format.customWith(formatterType)` — looks up
  converters by runtime type.

### `Serializer`

Static singleton. Methods:

| Method | Purpose |
|---|---|
| `Serializer.register<T>({fromJson, toJson})` | Register a non-union type. |
| `Serializer.registerUnion<T>({typeField, discriminator, fromJson})` | Register a union case. |
| `Serializer.toJson<T>(value)` | Encode to a JSON string. |
| `Serializer.fromJson<T>(json)` | Decode from a JSON string. |
| `Serializer.fromDynamic<T>(decoded)` | Decode from an already-decoded value. |
| `Serializer.encodeDynamic(value)` | Encode a runtime value to a JSON-compatible structure. |
| `Serializer.formatDate(value, pattern)` | Format a `DateTime` with a supported pattern (`'yyyy-MM-dd'`, `'iso8601'`). |
| `Serializer.parseDate(value, pattern)` | Parse a `DateTime` using a supported pattern. |
| `Serializer.reset()` | Clear the registry. (For tests.) |
| `Serializer.snapshot()` | Immutable snapshot of the current registry state. (For debugging / tests.) |
| `Serializer.validateMapKeys(map)` | Validate that the keys of a `Map` are safe JSON keys. |
