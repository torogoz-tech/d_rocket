# d_rocket 2.2.0

Release date: 2026-11-18

This release adds model-driven form capture to the d_rocket core. A model can
now remain the single source of truth for field metadata, conversion,
validation and request construction. The feature does not add widgets, a
Flutter-only dependency, or a second form model.

## Packages in this release

The Forms contract is split between the runtime and the generator:

```yaml
dependencies:
  d_rocket: ^2.2.0

dev_dependencies:
  d_rocket_builder: ^2.2.0
  build_runner: ^2.4.13
```

`d_rocket_engine_sqlite` remains compatible through its existing `^2.1.0`
dependency constraint. Forms do not depend on SQLite, REST or a particular
Flutter control.

## What was added

### Runtime (`d_rocket`)

- `@Form` opts a model into form adapter generation.
- `@FormField` supplies optional label, order and input metadata.
- `@Required`, `@Email`, `@Length`, `@Pattern` and `@Range` express model
  validation rules.
- `FormInput` describes the suggested input kind without selecting a widget.
- `FormFieldState<T>` exposes typed value, raw value, errors, stable error
  codes, touched state and generic bindings.
- `FormState<T>` coordinates validation and safe model construction.
- `FormValidationMode` supports `onChange`, `onBlur`, `onSubmit` and `manual`.
- `FormValueParser<T>` supports raw values from controls that do not emit the
  model's final Dart type.

### Code generation (`d_rocket_builder`)

The opt-in `form` builder emits:

```text
login_request.d_rocket_form.g.dart
```

For `LoginRequest`, the generated public adapter is `LoginRequestForm`. Its
output is independent from serializer, REST, ORM, migration and realtime
parts, so adding `@Form` does not change those generated namespaces.

The generated adapter includes:

- typed getters for every public model field;
- `bind()` for controls that already emit the declared Dart type;
- `bindRaw()` for text, numeric, boolean, date and enum controls;
- `validate()` and `build()`;
- ordered `FormFieldDefinition` metadata;
- deterministic conversion and validation error codes.

## Minimal model

```dart
import 'package:d_rocket/d_rocket.dart';

part 'login_request.d_rocket_form.g.dart';
part 'login_request.d_rocket_serializer.g.dart';

@Serializable()
@Form()
class LoginRequest {
  LoginRequest({required this.email, required this.password});

  @FormField(label: 'Email', order: 1)
  @Required(message: 'El correo es obligatorio')
  @Email(message: 'Enter a valid email')
  final String email;

  @FormField(
    label: 'Password',
    order: 2,
    input: FormInput.password,
  )
  @Required(message: 'Password is required')
  @Length(min: 8, message: 'Debe tener al menos 8 caracteres')
  final String password;
}
```

`@FormField` is optional. If it is omitted, the builder still includes the
public instance field using its Dart name and declaration order. Every public
field included by the form must be a named parameter of the unnamed
generative constructor; derived or computed fields should not be part of the
editable model.

## Binding any Flutter control

The generated API is deliberately control-agnostic:

```dart
final form = LoginRequestForm(
  validationMode: FormValidationMode.onSubmit,
);

TextFormField(
  onChanged: form.email.bind(),
  decoration: InputDecoration(
    labelText: 'Email',
    errorText: form.email.error,
  ),
)
```

The same field state can be connected to `TextField`, `Checkbox`, `Switch`,
dropdowns, date pickers or third-party controls. `flutter.Form` is optional;
it is only a visual/submission container and is not required by d_rocket.

For controls that emit raw values, use `bindRaw()`:

```dart
TextField(onChanged: form.amount.bindRaw()),
```

Invalid input and `null` sent to a non-nullable field produce
`conversion.invalid`. An unset non-nullable field also prevents `build()` from
constructing a partially valid model.

## Validation and REST integration

```dart
if (!form.validate()) {
  setState(() {});
  return;
}

final request = form.build();
final response = await authApi.login(request);
```

`build()` returns the original model type. The existing serializer and REST
builders then handle JSON and `@Body` serialization; the form runtime never
builds maps manually and never performs network or database work.

## Supported conversion matrix

| Model type | Typed binding | Raw binding | Null behavior |
|---|---:|---:|---|
| `String`, `String?` | Yes | Yes | Nullable values remain nullable. |
| `int`, `double`, `num` | Yes | Yes | Invalid/null non-nullable input is an error. |
| `bool` | Yes | Yes | Accepts boolean values and `true`/`false` text. |
| `DateTime` | Yes | Yes | Accepts `DateTime` or ISO-8601 text; `@Format.date` is honored. |
| enum | Yes | Yes | Raw enum names are matched against `values`. |
| exact `Decimal`/`BigDecimal` object | Typed only | No implicit conversion | Requires an explicit conversion contract. |

The last rule is intentional: silently converting an exact decimal value
object to `double` could lose precision. Decimal-compatible numeric fields
using `double`/`num` are covered by the normal numeric parser and ORM
conversion rules.

## Generated files and CI

Run generation after changing annotated models:

```bash
dart run build_runner build --delete-conflicting-outputs
dart analyze
dart test
```

Generated `.g.dart` files are build artifacts. They must be produced by
`build_runner`, not manually edited. A clean checkout must run the generator
before analysis or tests that import generated parts.

The release was verified with the full suites: 840 `d_rocket` tests (one
skipped) and 59 `d_rocket_builder` tests, plus a clean build in both packages.

## Upgrade from 2.1.0

No existing model needs to add `@Form`. Models without that annotation retain
their previous generated outputs. To adopt Forms:

1. Add `d_rocket_builder: ^2.2.0` as a dev dependency.
2. Add `@Form()` to the existing model.
3. Add validation annotations where the model owns the rule.
4. Add the `.d_rocket_form.g.dart` part.
5. Run `build_runner` and connect existing controls through `bind()` or
   `bindRaw()`.

The serializer, REST and ORM parts remain independent and continue using their
existing annotations and generated files.
