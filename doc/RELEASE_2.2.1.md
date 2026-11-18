# d_rocket 2.2.1

Release date: 2026-11-18

This patch release improves pub.dev discoverability and documentation. It
does not change the Forms runtime or generated API introduced in 2.2.0.

## Package metadata

The package description is now a concise 60–180 character summary suitable
for pub.dev search results. The package version is `2.2.1` and remains
compatible with the `d_rocket_builder 2.2.1` release.

## Documentation fixes

- The README now presents Forms as framework layer 7.
- Layer links point to the repository's top-level `doc/` directory.
- Historical status and release documents use valid repository URLs.
- The Forms release guide covers installation, bindings, conversion,
  nullability, Decimal policy, REST integration, CI and migration.

## Upgrade

```yaml
dependencies:
  d_rocket: ^2.2.1

dev_dependencies:
  d_rocket_builder: ^2.2.1
```

No model changes are required when upgrading from 2.2.0.
