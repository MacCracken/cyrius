# Raise the per-build compile-source-size cap from 2 MB → 4 MB

**Filed:** 2026-05-10 during `t-ron` 2.1.x modernization arc
**Severity:** Medium — workaround exists (per-module dep pulls
instead of dist-bundle pulls), but it forces consumers off the
first-party-floor distribution pattern that libro / bote / patra /
agnosys / majra all standardized on
**Affects:** Cyrius parser / source-buffer machinery, `cc5`
5.10.x

## Summary

Cyrius rejects a build when the preprocessed source — the
concatenation of `src/main.cyr` plus every transitive
`include "<file>"` — exceeds 2 MB:

```
error: expanded source exceeds 2MB (2097606 bytes)
FAIL
```

The cap is a hard limit on the in-memory source buffer the
parser operates over. It is not the same as `string_data`
(intern table for string literals, 2 MB cap with a small fraction
used today) or `code_size` (emitted-code buffer, separately
capped at 1 MB).

`t-ron` 2.1.0 hit this cap when attempting to consume both
`libro 2.6.2`'s `dist/libro.cyr` (single-file bundle, 5 546
lines / 175 KB) AND `bote 2.7.1`'s `dist/bote.cyr` (single-file
bundle, 4 857 lines / 175 KB) under the modernized dep-bundle
pattern. The combined `lib/` set after `cyrius deps` totals
**61 312 lines** of stdlib + first-party bundles before any
`src/*.cyr` is added; once preprocessed against `t-ron`'s 19
source modules, the expanded source crosses 2 MB.

This proposal asks to **raise the cap to 4 MB** (doubling the
in-memory source buffer). 4 MB covers `t-ron`'s realistic
foreseeable composition and matches the next power-of-two
breakpoint; the memory cost is negligible on modern systems; no
language-level redesign is required.

## Reproduction

`t-ron`'s 2.1.0 attempt to use both dist bundles directly:

```toml
# cyrius.cyml

[deps]
stdlib = [
    "string", "fmt", "alloc", "vec", "str", "syscalls", "io",
    "args", "tagged", "assert", "fnptr", "hashmap", "regex",
    "chrono", "freelist", "thread", "sakshi", "bigint", "json",
    "base64", "sigil", "net", "tls", "sandhi", "ws_server", "ct",
]

[deps.libro]
git = "https://github.com/MacCracken/libro"
tag = "2.6.2"
modules = ["dist/libro.cyr"]

[deps.bote]
git = "https://github.com/MacCracken/bote"
tag = "2.7.1"
modules = ["dist/bote.cyr"]
```

`src/main.cyr` includes both bundles + the full stdlib. Build:

```
$ CYRIUS_DCE=1 cyrius build src/main.cyr build/t-ron
compile src/main.cyr -> build/t-ron [x86_64]
error: expanded source exceeds 2MB (2097606 bytes)
FAIL
```

The actual workaround `t-ron` applied (per-module bote pull,
libro stays on the dist bundle for its `#derive(accessors)`
machinery), documented in `t-ron` CHANGELOG 2.1.0:

```toml
[deps.libro]
tag = "2.6.2"
modules = ["dist/libro.cyr"]    # dist needed for accessors

[deps.bote]
tag = "2.7.1"
modules = [
    "src/error.cyr",
    "src/protocol.cyr",
    "src/jsonx.cyr",
    "src/codec.cyr",
    "src/registry.cyr",
    "src/events.cyr",
    "src/audit.cyr",
    "src/dispatch.cyr",
    "src/schema.cyr",
]
```

This split fits under the 2 MB cap but **breaks the
ecosystem-uniform pattern** that libro / bote / patra / agnosys /
majra all advertise via their `DEPS-PATTERN.md` files
("consumers wire one `modules = ["dist/<crate>.cyr"]` line per
dep"). `t-ron`'s `DEPS-PATTERN.md` has had to document a
"deviation" section explaining why this single repo cherry-picks
bote modules.

## Why the buffer fills so fast

The expanded source for a moderate consumer is dominated by the
transitive stdlib brought in by bote's transport stack:

| Module | Lines | Notes |
|---|---:|---|
| `lib/sandhi.cyr` | 11 729 | HTTP server primitives |
| `lib/agnosys.cyr` | 10 028 | TPM / syscall wrappers (transitive via libro / sigil) |
| `lib/sigil.cyr` | 8 973 | Ed25519 / SHA-256 / AES-GCM primitives |
| `lib/libro.cyr` | 5 546 | dist bundle |
| `lib/bote.cyr` | 4 857 | dist bundle |
| `lib/patra.cyr` | 4 823 | Storage primitives (transitive via libro) |
| `lib/majra.cyr` | 3 127 | PubSub (transitive via bote) |
| `lib/json.cyr` | 1 439 | stdlib |
| `lib/regex.cyr` | 1 180 | stdlib |
| `lib/sakshi.cyr` | 1 133 | structured logging |
| `lib/tls.cyr` | 694 | stdlib |
| ... | | |
| **Total** | **61 312** | (with `t-ron`'s manifest) |

Six modules account for ~85 % of the line count, all of them
first-party. None is `t-ron`-specific — every MCP-shaped consumer
(daimon, phylax, future sutra / jalwa / rasa / mneme work) will
pull the same neighbourhood. The cap is not a `t-ron`-only
problem; it is structural for "consumers of bote + libro under
the dist-bundle contract".

DCE eliminates ~98 % of these bytes from the emitted binary
(`t-ron`'s 1.12 MB ELF post-DCE vs 60 KB+ of source per module),
but DCE is post-parse — the cap is enforced on the pre-DCE
expanded source.

## What other languages cap at

Surveyed the mainstream landscape; **none has a hard cap on
preprocessed-source-buffer size:**

| Language | Cap | Notes |
|---|---|---|
| C (GCC, Clang) | none | Translation unit can be arbitrarily large; only practical limit is the host's address space |
| C++ (Clang, MSVC) | none | Same, plus modules / PCH for large headers |
| Java (javac) | none on source; bytecode methods cap at 65535 bytes (a different ceiling) |
| Rust (rustc) | none | Crate sources can be hundreds of MB; LLVM IR scales |
| Go | none | Effectively bounded by package size, no fixed limit |
| Python | none | Bytecode methods cap separately |
| Swift, C# | none |
| Cyrius (5.10.x) | **2 MB** | The only language we found with a hard per-build source-size cap |

**Style / static-analysis recommendations** (not language
limits): "large translation units" warnings exist in cyclomatic-
complexity tooling, but no compiler refuses to build. The cap is
again an implementation detail of Cyrius's in-memory parser state
leaking into the language surface.

## Real-world incidence

| Consumer | Combined dep set | Source size | Cap pressure |
|---|---|---|---|
| **t-ron 2.1.0** | libro 2.6.2 dist + bote 2.7.1 dist + stdlib | ~2.05 MB | **Over (workaround in CHANGELOG)** |
| **t-ron 2.1.0 (workaround)** | libro 2.6.2 dist + bote 2.7.1 per-module (9 files) + stdlib | ~1.6 MB | Under |
| **bote 2.7.1** (own build, src + transitive libro dist + majra) | ~1.5 MB | Under but tightening as transports grow |
| **libro 2.6.2** (own build, src + transitive sigil / patra / agnosys) | ~1.3 MB | Under |
| **daimon** (projected, when it adopts t-ron + bote + libro under the same contract) | similar to t-ron | **Will hit cap** |
| **phylax** (projected) | similar | **Will hit cap** |

The pattern is clear: **any consumer of two or more first-party
dist bundles plus a moderate stdlib slice already pushes against
2 MB.** The cap will fire in daimon / phylax the same way it
fired in t-ron, forcing each to deviate from the
ecosystem-uniform `modules = ["dist/<crate>.cyr"]` pattern.

## Cost analysis

The cap is the in-memory size of the **source buffer** the
parser operates over. Doubling to 4 MB:

- **Memory:** +2 MB per parser invocation. Allocated once at the
  start of compile, released at end. On a 16 GB CI runner this
  is 0.012 % of available RAM. Even on a 2 GB embedded host this
  is 0.1 %.
- **Code:** likely a single literal (`2 * 1024 * 1024` →
  `4 * 1024 * 1024`) at one allocation site. From outside the
  compiler I can't confirm the exact LOC; the maintainer's PR
  would be small.
- **Risk:** zero functional change — the cap is a ceiling, not a
  pre-allocation. Builds that fit under 2 MB are unaffected.
- **Backward compatibility:** strictly additive. Code that
  compiled at 2 MB still compiles at 4 MB.

## Recommendation

### Option A: Raise to 4 MB (preferred)

Bump the cap. One mechanical patch. Covers all current
first-party consumers (t-ron, projected daimon / phylax) and
matches the next power-of-two breakpoint. We are not asking for
unlimited; we are asking for 2× more.

### Option B: Raise to 8 MB

Same shape, more headroom. Argument: "do it once, never come
back" — the next composition layer (a hypothetical aggregator
that bundles 3+ first-party dists, e.g. daimon-with-all-sinks)
could plausibly hit 4 MB by 2027. Argument against: still a
magic number; if 4 MB covers everything we know today, do not
quadruple. Pick A unless a maintainer wants the bigger jump on
principle.

### Option C: Make it dynamic

Replace the fixed-size source buffer with a growable buffer
(`realloc` on hit). Removes the cap entirely. Cost: more
invasive than a literal bump and changes parser memory ownership
semantics. Nice-to-have eventually; not necessary today.

### Option D: Keep at 2 MB but improve the diagnostic

If the project values the cap as a "you are doing too much"
signal, keep 2 MB but make the error message say so:

```
error: expanded source exceeds 2MB (2097606 bytes)
  hint: consumers of multiple dist bundles often hit this —
  consider per-module pulls for one of the deps, or split the
  build into compile units. See t-ron's cyrius.cyml [deps.bote]
  per-module pattern as a worked example.
```

Not preferred from outside the compiler — the cap is forcing
ecosystem-wide non-uniformity — but it's a viable middle ground.

## Severity rationale

MEDIUM. Higher than the return-statement cap raise filed
2026-05-08 (which was LOW because the workaround was mechanical
and arguably more readable). This cap forces every consumer of
the first-party-floor pattern off that pattern, undermining a
deliberate ecosystem investment (the `DEPS-PATTERN.md`
contract). t-ron has documented the deviation; daimon / phylax
will do the same; eventually the deviation becomes the norm and
the contract is meaningless.

## What we're doing in t-ron

t-ron 2.1.0 shipped the per-module-bote workaround because the
cut needed to land for the user. The split is documented in the
2.1.0 CHANGELOG under `### Pending / parked`:

> **Full dist-bundle dep adoption (bote)** — blocked on either
> a cyrius compile-source-size cap raise or a bote opt-in
> profile that excludes the transport stack (sandhi/tls/ws_server).
> Today the two dist bundles together expand past 2 MB.

t-ron's `cyrius.cyml [deps.bote]` carries an inline comment
referencing this proposal:

> bote MCP core — per-module pull. bote's single dist bundle
> drags the full transport stack (sandhi 11k lines, tls,
> ws_server) which pushes t-ron's expanded source past cyrius's
> 2 MB compile cap when paired with libro's dist bundle. […]
> Dist-bundle adoption is parked as a later 2.1.x candidate
> gated on either a cyrius cap raise or a bote opt-in profile
> that excludes transports.

Companion proposal: see `bote/docs/development/issues/2026-05-10-opt-in-transport-profile.md`
for the bote-side option. Landing either unblocks t-ron;
landing both gives consumers a choice.

If this proposal lands and the cap goes to 4 MB, t-ron 2.1.x
will close the parked "Future" row in its roadmap by flipping
`[deps.bote]` to the dist-bundle form and dropping the
per-module enumeration.
