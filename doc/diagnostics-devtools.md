# d_rocket diagnostics and Flutter DevTools

Enable diagnostics only in development:

```dart
DrocketDevToolsBridge.register();
```

By default, request and response bodies are hidden while their method, URL,
status, headers names, and body sizes remain available. During local
development, payload capture can be enabled explicitly:

```dart
DrocketDevToolsBridge.register(includeSensitiveData: true);
```

Use payload capture only with non-sensitive development data.

This enables the bounded in-memory event buffer and registers the VM Service
endpoints consumed by the bundled `d_rocket` DevTools extension. The extension
is available when DevTools is connected to an application that depends on
`d_rocket`.

The event model is shared by REST, SQLite, migrations, sync, LINQ, cache, and
realtime integrations. Events are disabled by default, capped at 500 entries,
and do not include request bodies, headers, bind values, or SQL text unless the
application explicitly enables `includeSensitiveData`.

The extension exposes category filters, refresh, and clear-history actions.
The core package remains Flutter-independent; only the extension package uses
Flutter and `devtools_extensions`.
