# Embed data files as source strings — an `[embed]` / assets manifest section

**Filed:** 2026-08-10 (by an agnosai consumer during its v2.0.0 Rust→Cyrius port —
surfaced porting `definitions/loader.rs`, whose 18 built-in presets are
`include_str!`'d into the binary)
**Status:** PROPOSED — an **ergonomics gap**, not a capability gap. Everything
below is already achievable with a generated `.cyr`; the ask is to stop every
consumer hand-rolling the same generator.
**Placement:** **Interleaved reactive fold-in, v6.5.x — named first candidate.**

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⭐ **ITS PREREQUISITE HAS CLEARED.** Sequenced behind `2026-06-25-source-level-version-constant`, which **SHIPPED at v6.5.21** and is archived — so it is now schedulable. `PP_EMIT_PKGVER` (`src/frontend/lex_pp.cyr`) is the template for a `#@embed` arm and cbt's `_materialize_source` marker write for the emission side. ⚠ HARD CONSTRAINT LEARNED AT .21: an injected directive must emit **ZERO newlines** (merge onto the following source line) or it shifts every `<source>` diagnostic by one — a 1-for-1 line replacement is NOT line-neutral.
**Priority:** low / not a release-blocker. agnosai ships its own generator and is
not waiting on this.
**Siblings:** [`2026-06-25-source-level-version-constant.md`](2026-06-25-source-level-version-constant.md)
(same shape, one value: a build-time value that source cannot read) and
[`2026-07-05-const-eval-comptime.md`](2026-07-05-const-eval-comptime.md), which
notes that "the generated-`.cyr` idiom already covers the *bulk* of
compile-time-data needs". This proposal is about making that idiom a first-class
manifest feature rather than a per-project script.

## Trigger (the concrete case)

`rust-old/src/definitions/loader.rs` embeds eighteen preset JSON files —
810 lines total — with `include_str!`:

```rust
pub fn builtin_presets() -> Vec<PresetSpec> {
    let jsons = [
        include_str!("../presets/quality-lean.json"),
        include_str!("../presets/quality-standard.json"),
        // … 16 more
    ];
    jsons.iter().filter_map(|j| load_preset_from_json(j).ok()).collect()
}
```

The point is that the binary is **self-contained**: `GET /api/v1/presets` answers
from data baked into the executable, with no `presets/` directory to deploy and
nothing to go missing. A runtime `read_dir` would be a behavioural change, not an
implementation detail — a deployed binary without the directory answers `[]`
where the oracle answers 18.

## What Cyrius has today (verified, not assumed)

Tested against cyrius 6.5.16 before filing:

| mechanism | works? | note |
|---|---|---|
| textual `include "path.cyr"` of a file holding `var X = "…";` | ✅ | the working idiom |
| string literal spanning physical lines | ✅ | so JSON keeps its formatting |
| `-D NAME` reaching source via `#ifdef` | ✅ | build-time switches |
| `modules = [...]` in `[build]` / `[lib]` / `[lib.X]` / `[deps.X]` | ✅ | can list a generated file |
| raw strings — `r#"…"#`, `r"…"`, `` `…` `` | ❌ | all rejected |
| an `[embed]` / `[assets]` manifest section | ❌ | no such section |

The manifest sections `cbt` parses are `[package]`, `[groups]`, `[features]`,
`[deps]`, `[deps.NAME]`, `[build]`, `[lib]`, `[lib.PROFILE]`, `[modular]`. There
is no way to name a **data** file and have its bytes reach source.

So the gap is not "impossible", it is "every project writes the same escaper".

## The cost, concretely

To embed those 18 files agnosai must:

1. write a generator that reads each `.json`, escapes `"` and `\`, and emits
   `var AGNOSAI_PRESET_<NAME> = "…";`
2. check the generated `.cyr` in, because a build must not depend on a script
   having been run
3. keep it in sync — a preset edited without re-running the generator ships stale
   data, and **nothing detects it**. That is the same silent-drift failure mode
   the `${file:VERSION}` proposal was filed for: sit's banner drifted for six
   releases before an audit caught it.

Point 3 is the real cost. A checked-in generated artifact with no freshness gate
is a drift hazard, and each consumer invents its own (or does not).

## Suggested shape (maintainer's call)

A manifest section naming files and the symbols they become:

```toml
[embed]
AGNOSAI_PRESET_QUALITY_LEAN = "src/presets/quality-lean.json"
# or, for a set:
presets = { dir = "src/presets", glob = "*.json", prefix = "AGNOSAI_PRESET_" }
```

`cbt` reads each file, escapes it, and makes the bytes available to source as a
string constant — the same way `${file:VERSION}` already reads a file for
`[package].version`, but surfaced to *source* rather than to manifest metadata.

Three properties that would matter more than the syntax:

- **Freshness is the compiler's job, not the consumer's.** Whatever the shape,
  the win over a generator script is that a stale embed becomes impossible rather
  than merely detectable.
- **Bytes, not just text.** `include_bytes!` has the same shape and a binary
  asset (an icon, a WASM module, a test fixture) has the same problem. If the
  section only ever handles UTF-8, say so explicitly.
- **Size discipline.** Embedding is `.rodata`; a consumer that embeds 40 MB
  should learn that from the build, not from the binary. A warning threshold
  would be in keeping with the existing "large static data" note.

## What agnosai is doing meanwhile

Shipping the generator: a script escapes the 18 presets into a checked-in
`src/definitions/presets_data.cyr`, listed in the manifest. **Nothing is
blocked.** This is filed because the idiom is now on its third consumer by
cyrius's own count, and because the drift hazard in point 3 is the kind of thing
that is cheap to solve once upstream and expensive to solve eighteen times
downstream.
