# Release cadence

> **Effective from `d_rocket 2.0.0`.** From this release onwards,
> new `d_rocket` integrations ship on a **monthly cadence**. The core
> runtime and builder are coordinated; optional bindings, lints and engines
> may advance on compatible independent version lines.

## The policy

- **Minor and major releases** ship on the **first Tuesday of
  every month** (or the next business day if that Tuesday is a
  public holiday in the maintainer's locale).
- **Patch releases** (bug fixes, security fixes, doc-only fixes)
  can ship at any time against the latest minor version. A
  patch release does not skip the next monthly minor.
- **Pre-release versions** (`2.5.0-dev`, `2.5.0-beta`) can be
  tagged at any time but do not count toward the monthly
  cadence. They are tagged at the maintainer's discretion when
  enough of a new feature is stable enough to need early
  integration.

## Package version lines

A coordinated core release updates `d_rocket` and
`d_rocket_builder` together. Other packages are compatible dependencies,
not automatic lockstep participants:

| Package family | Current local line |
|---|---|
| `d_rocket` + `d_rocket_builder` | `2.5.0` |
| `d_rocket_flutter` | `2.4.0` |
| `d_rocket_lints` | `2.3.0` |
| `d_rocket_engine_sqlite`, `d_rocket_engine_postgres`, `d_rocket_engine_web`, `d_rocket_engine_mobile` | `2.1.0` |

Consumers should follow the compatibility table in each release guide and
pin the core and builder constraints explicitly when using code generation.

## Release sequence

The 2.5.0 release candidate is prepared locally and has not been pushed or
published. Future minor releases follow the monthly policy; exact dates are
recorded in the corresponding GitHub milestone.

| Version | Date |
|---|---|
| `2.5.0` | release candidate; date set at publication |
| `2.6.0` | first Tuesday after the 2.5.0 release |

## What "integration" means in this context

For consumers of `d_rocket`, an "integration" is a single
release of a new minor or major version. Integrating a new
release is:

1. Update the `d_rocket: ^2.x.y` constraint in `pubspec.yaml`.
2. Read the release notes for breaking changes (the major
   releases are the only ones that ship breaking changes; minor
   releases add features in an additive way).
3. Run `dart run build_runner build --delete-conflicting-outputs`
   to refresh the generated `*.d_rocket_*.g.dart` files if any
   annotation parameter changed.
4. Run the project test suite.

The migration guide for each major release is in
[`doc/11-migration-1-x-to-2-0.md`](11-migration-1-x-to-2-0.md)
(1.x → 2.0) and a future equivalent file per future major
release.

## What triggers an out-of-band patch release

A patch release can ship at any time, without waiting for the
monthly cadence, in the following cases:

- **Security**: a CVE is filed against a transitive
  dependency and the pinned version is past EOL.
- **Data integrity**: a bug that can cause silent data loss
  (e.g. the B-09 validation gap, a SQL push-down that emits
  wrong results on a specific `Expr` shape).
- **Build breakage**: a released `2.x.y` fails to compile on a
  `Dart 3.x` minor that the package claimed to support.

The patch release updates the affected package family and any package that
must remain compatible with it. Core and builder remain coordinated when the
generated contract changes.

## When a monthly release is skipped

A monthly minor is skipped when:

- No new feature has been merged since the previous monthly
  release.
- The maintainer publishes a `Re: not this month` comment in
  the milestone on the source repository.

A monthly minor is **never** skipped due to a bug — bugs are
shipped as patch releases against the previous minor.

## How to know when a release ships

The release is announced in three places:

1. The [GitHub Releases page](https://github.com/torogoz-tech/d_rocket/releases)
   of the source repository.
2. The `CHANGELOG.md` of every public package (regenerated
   automatically from the release tag).
3. A new entry in [`STATUS.md`](STATUS.md) listing the version, the date,
   package versions and headline changes.

The release is **not** announced on Twitter, Discord, or any
external channel — those channels are for high-level project
news, not for individual release announcements.

## Versioning

`d_rocket` follows [Semantic Versioning 2.0.0](https://semver.org/):

- A **patch** bump (2.0.0 → 2.0.1) is a bug fix that does not
  change the public API.
- A **minor** bump (2.0.x → 2.1.0) adds features in an
  additive way (new annotations, new operators, new engine
  packages). No existing user code is broken.
- A **major** bump (2.x.y → 3.0.0) is a release that breaks
  public API. A migration guide ships in the same tag.

The 1.x line is in **maintenance mode**: bug fixes and security
patches only, no new features. New development happens on the
2.x line.
