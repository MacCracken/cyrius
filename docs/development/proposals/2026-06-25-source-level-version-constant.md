# Source-level VERSION constant — build-time injection of the package version into Cyrius source

**Filed:** 2026-06-25 (by a sit consumer — sit 1.0.4, the `/sit/v1/capabilities`
server-identity banner)
**Severity:** Build/manifest ergonomics gap — `cyrius.cyml`'s `${file:VERSION}`
interpolation is **manifest-metadata only** (`[package].version`). There is no way
for *source code* to read the package version at build time, so any program that
must emit its own version string (a server identity header, a `--version` flag, a
wire-protocol banner) hand-maintains a string literal that silently drifts from
`VERSION`.
**Affects:** sit (the `/sit/v1/capabilities` `"sit":"X.Y.Z"` banner — drifted to
`0.8.10` and stayed there through six releases before a 1.0.4 audit caught it), and
any first-party binary that surfaces its own version: most CLIs with `--version` /
`-V`, and any server emitting an identity / `Server:` header. The pattern recurs
across the first-party fleet.
**Target slot:** a v6.x build/manifest feature — maintainer direction. **Not a
blocker:** sit ships **1.0.4** with a CI guard (assert the hand-bumped literal ==
`VERSION`) as the stopgap; this proposal removes the hand-bump entirely.
**Template:** the existing `${file:VERSION}` manifest interpolation is the precedent
— extend the same file-read to a source-visible constant.

## Trigger

sit's `serve` exposes a `GET /sit/v1/capabilities` endpoint that emits a JSON
identity banner: `{"sit":"X.Y.Z","max_body":...,"auth":[...]}`. The `"sit"` version
literal was hand-bumped each release, guarded only by a code comment ("closeout pass
before tagging asserts the literal matches"). That assertion was a *manual* process
with no automated check — so the literal silently drifted to **`0.8.10`** and stayed
there across `0.8.11`, `0.8.12`, `1.0.0`, `1.0.1`, `1.0.2`, and `1.0.3` until a 1.0.4
audit found it ~7 releases stale.

sit 1.0.4 added a CI step asserting `banner-literal == VERSION`, which *detects* drift
at release time — but the maintainer still hand-edits **two** places (the `VERSION`
file and the source literal) on every tag, and the guard is a backstop for a mistake
that shouldn't be possible in the first place.

## The gap

`cyrius.cyml` resolves `${file:VERSION}` into `[package].version` (manifest metadata),
and `cyrius distlib` stamps a `# Version:` comment into the generated bundle. But
nothing exposes the version to **compiled source**. A program that needs its version
at runtime has only two options today, both unsatisfactory:

- **(a) hardcode a string literal** — drifts from `VERSION` the moment a release
  forgets to bump it (exactly what happened to sit); or
- **(b) read + parse the `VERSION` file via syscalls at runtime** — adds a filesystem
  dependency and a failure path for a value that is fully known at build time, and
  breaks the "single static binary, no runtime-fs assumptions" model first-party tools
  rely on.

The value is already resolved by the toolchain for `[package].version`; it simply
isn't reachable from source.

## Proposed surface (sketch — maintainer to shape)

A few possible shapes, maintainer to pick:

1. **A predefined source constant the build injects** — e.g. a `CYRIUS_PKG_VERSION`
   cstring (and perhaps `CYRIUS_PKG_NAME`) visible to every source file in the
   package, resolved from `[package].version` (which already pulls `${file:VERSION}`).
   Analogous to C's `__VERSION__`, Rust's `env!("CARGO_PKG_VERSION")`, Go's
   `-ldflags -X` injection. **Minimal first cut** — no new manifest surface.
2. **Manifest → generated constant file** — a `[build]` codegen step (or built-in)
   that emits a `src/version.cyr`-style constant (`var PKG_VERSION = "X.Y.Z";`) before
   compile, auto-included. More general but adds a build phase.
3. **`${file:...}` interpolation inside source string literals** — extend the existing
   manifest interpolation so a `str` literal in source can carry a build-time
   `${file:VERSION}` / `@embed("VERSION")` expansion.

Option (1) is the smallest viable change and covers the motivating cases.

## What it unblocks

- **sit** — drop the hand-bumped serve banner *and* the CI guard stopgap; the
  `/sit/v1/capabilities` identity always matches the running binary.
- **Any first-party CLI** — a `--version` / `-V` that can't lie, with a single source
  of truth and no runtime fs read.
- **Any server identity / `Server:` header** across the fleet — same property.

## Honest scope note

Low-severity, high-ergonomics. The CI-guard stopgap fully prevents *shipping* drift
today, so nothing is broken right now. This proposal removes a manual, easily-forgotten
per-release bump from every binary that surfaces its version — turning "remember to
edit two files and hope CI catches it" into a value the build owns. The risk it
eliminates is precisely a human-edited literal diverging from the manifest value.

## References

- **sit 1.0.4** — the serve-banner drift and the CI-guard stopgap: sit
  `CHANGELOG.md` `[1.0.4]`; `src/serve.cyr` `serve_build_capabilities()`;
  `.github/workflows/ci.yml` "Verify version consistency" step.
- Prior art — C `__VERSION__`, Rust `env!("CARGO_PKG_VERSION")`, Go `-ldflags -X`
  linker variable injection.
- cyrius `${file:VERSION}` manifest interpolation (`cyrius.cyml [package].version`)
  — the existing file-read precedent this extends.

---
*Filed from sit 1.0.4. Consumer-side context lives in sit's CHANGELOG `[1.0.4]` and
`docs/development/roadmap.md` (the `1.0.x` patch line).*
