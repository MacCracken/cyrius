# Source-level VERSION constant — build-time injection of the package version into Cyrius source — ✅ SHIPPED v6.5.21

> **✅ SHIPPED in v6.5.21** (CHANGELOG `[6.5.21]`), one release EARLIER than its
> `.22` pin — pulled forward by maintainer direction. Option 1 as committed: a
> single injected source-visible cstring, no new manifest surface, no const-eval.
>
> **Mechanism:** cbt resolves `[package].version` and emits `#@pkgver <version>`
> into the materialized source; cycc's `PP_EMIT_PKGVER` replaces that line with
> `var CYRIUS_PKG_VERSION = "X.Y.Z";`.
>
> ⭐ **It emits ZERO newlines, and that is the whole design.** Every other thing
> cbt prepends shifts `<source>` diagnostics down by one — measured at 6.5.20,
> `-D FOO=1` moves a line-5 error to `:6` and a one-include `[deps] stdlib` does
> the same, uncompensated; only `#@incdir` was ever accounted for. The declaration
> is merged onto the front of the user's first line instead, so a defect on user
> line 3 still reports `:3:`. (A first cut replaced the line 1-for-1 and was NOT
> neutral — adding a line shifts everything regardless of what the line contains.)
>
> ⛔ **This proposal's premise — and the roadmap's — was FALSE in one load-bearing
> respect.** `roadmap.md` scoped the work as surfacing "`[package].version`
> (which already resolves `${file:VERSION}`)". Nothing resolved it. The only
> `${file:VERSION}` expander in the tree, `bayan_cyml_expand_value`
> (`lib/bayan.cyr`), has **zero callers**; bayan is not in cbt's include set; and
> `cyrius package` printed **"unknown"** for a manifest plainly declaring a
> version. So the slot had to WRITE a `[package].version` reader and a portable
> `${file:}` expander, not plumb an existing one.
>
> **The value is strictly validated** — `[0-9A-Za-z._+-]`, max 64 — because it
> lands inside a `"..."` literal and a manifest is consumer-controlled input. A
> `version` field of `1.0"; syscall(60,42); var z = "` cannot inject; the constant
> is simply absent and the use site fails with `undefined variable`. Absent beats
> wrong, which is precisely the failure sit filed.
>
> **Known limitation, stated rather than papered over:** the marker rides the
> existing source-materialization path, so it reaches any project with deps,
> defines, modules, or a subdir source — including sit — but not a bare flat
> `cyrius build one.cyr out` with no manifest deps. Forcing materialization there
> would create a `/tmp/cyrius-<pid>` directory on EVERY invocation, and those are
> never `rmdir`'d (`sys_rmdir` is absent on the Windows peer and `cbt/` cross-
> compiles to PE — see `cbt/build.cyr` `_cbt_tmpdir`). Turning a bounded leak into
> a per-build one to widen a convenience was the wrong trade; closing it needs a
> PE `rmdir` reroute.
>
> **Downstream:** sit can now drop the hand-bumped `serve.cyr` banner literal and
> its CI guard. Note sit has moved to **1.3.5** and pins cyrius **6.5.4**, so it
> needs a pin bump before it can consume this.

**Status:** ✅ **SHIPPED in v6.5.21.** Committed scope was the injected
source-visible `CYRIUS_PKG_VERSION` constant (the `${file:VERSION}` file-read
surfaced to source), NOT a general const-eval — delivered as scoped.
**Placement:** ~~v6.5.22 — the DX / diagnostics finish-out release~~ → **landed
v6.5.21** (pulled forward; the third pin held).
⚠ **This proposal has now lapsed TWO soft pins and this is the third; it gets a hard slot, not
another window.** Pin 1 said "fold into the next 6.4.x arc's closeout / an absorber band" — that
minor closed at **v6.4.86** without it. Pin 2 re-homed it as roadmap.md W1 item 8, window
`.4`–`.16` — we are at **.19** and it is unspent. The mechanism of both lapses is the same and
structural: its placement lived only in prose, in a slot-table row nobody re-derived. Hence the
`**Placement:**` line you are reading, now required on proposals as well as issues.
Premise re-checked 2026-08-11 at v6.5.19: `grep -rn PKG_VERSION src cbt lib scripts` → **0
hits**, and there is no partial implementation to build on — `PP_PREDEFINE`
(`src/frontend/lex_pp.cyr:1892`) stores value `0` unconditionally and `PP_DEFINE` (`:1907`)
parses values as **decimal digits only**, so even a `-D NAME=VALUE` workaround cannot carry a
version string.
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
