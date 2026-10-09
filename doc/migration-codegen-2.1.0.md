# Migration codegen — 2.1.0 changelog notes

## Implemented behaviour

`dart run d_rocket:migration add <name>` now has an opt-in codegen mode:

```bash
dart run d_rocket:migration add add_note_to_patients \
  --db app.db \
  --entities lib/db/entities.dart
```

The CLI invokes the schema-diff worker used by `migration check`, converts its
JSON payload into `CliSchemaDiff` values, and passes them to the pure migration
renderer in `lib/src/cli/migration_codegen.dart`.

## Generated output

- Safe diffs are emitted as `exec(...)` statements in `up()`.
- Clean inverses are emitted in `down()`.
- Executable unsafe diffs are included in `up()` and marked with visible
  review warnings.
- Changes without executable SQLite SQL are emitted as `MANUAL REQUIRED`
  blocks instead of invalid `exec(...)` calls.
- `--include-unsafe` remains accepted as a compatibility/acknowledgment flag.
- `--irreversible` emits an explicit `UnsupportedError` in `down()`.
- Empty diffs produce a reviewable no-op body instead of silently pretending
  that a schema change was generated.

## Safety model

The command never applies the generated migration. It only writes source code.
Destructive schema changes are generated but require explicit human review.
The CLI prints a direct warning, and the generated source includes the diff
reason and operation type so it can be checked before execution.

## Regression coverage

`test/bin/migration_codegen_test.dart` covers JSON conversion, safe/unsafe
partitioning, inverse SQL, raw-string escaping, generated `up()`/`down()`
bodies, executable versus manual unsafe operations, irreversible migrations,
and deterministic class/file naming.
