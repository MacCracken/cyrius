> **RESOLVED — v6.3.41 (2026-07-03).** Cap raised **1024 → 4096**. Root: the `gvar_toks`
> deferred-init table (`src/frontend/parse_decl.cyr`) was an 8 KB array at `0x198000`
> (1024 × 8 B), boxed in by `jump_target_cnt` at `0x19E000` — an array bound, NOT an
> ABI/offset constraint. Relocated to the reclaimed `0x729000[32768]` band (the .27
> output_buf gap, below TS@0x800000, verified free across all targets); both `>= 1024`
> checks + the `EMIT_GVAR_INITS` reader retargeted to 4096. **Counting rule documented** in
> the language guide's *Global Initializers* section: only a NON-literal top-level `var =`
> (call/ident/expr) consumes a slot; bare integer-literal inits take the static-init fast
> path and enum members are const-folded — neither counts. Fixture
> `tests/tcyr/many_initialized_globals.tcyr` (1100 call-init globals: fails old cap-1024,
> passes new). The stale "256 initialized globals" figure lives only in downstream
> first-party `CLAUDE.md` files (this repo carried none) — reconcile spawned as a separate
> task. Default codegen byte-identical; fixpoint + seed→cybs→cycc + ecb/cass/pi SELFHOST_OK.
> See CHANGELOG [6.3.41]. *(Archived.)*

# Raise (or make configurable) the `max 1024 initialized globals` per-compilation-unit cap

**Filed:** 2026-07-03 (surfaced integrating sit's `.git/` read-mode into thoth — a large app
that vendors several first-party dist bundles into one compilation unit).
**Severity:** P2 — not a miscompile; a hard **capacity ceiling** that forces downstreams to
carve artificially-lean dist profiles to fit. Grows worse as first-party apps vendor more
bundles into a single unit.

## WHICH cap — read this first (three distinct limits, do not conflate)

This is about **ONE** specific limit:

- **THIS ISSUE →** `too many initialized globals (max 1024)` — the **initialized-globals**
  count per compilation unit (the `gvar_toks` slots): every top-level `var NAME = <initializer>;`
  consumes one slot. Emitted as `error:<file>:<line>: too many initialized globals (max 1024)`.

It is **NOT** any of these (each is a different cap, tracked/handled separately — calling them
out so the fix targets the right counter):

- **NOT** the aarch64 **output-size** cap — `error: output too large (…/16777216 bytes)` (a
  16 MiB emitted-binary ceiling; a size limit, not a global-slot count).
- **NOT** the **4096 variables** / **1024 functions** per-compilation-unit limits (documented
  alongside this one in first-party CLAUDE.md files as "Max limits per compilation unit: 4,096
  variables, 1,024 functions, 256 initialized globals" — note that doc says **256**, but the
  live 6.3.x compiler errors at **1024**; the doc is stale and should be reconciled too).

**Enum members do NOT consume the initialized-globals budget** (verified: a program with **1200
enum members** compiles clean — well past 1024). Only top-level `var … = …` do. This is why the
first-party guidance is "use enum values for constants — don't consume gvar_toks slots"; but it
only helps for *constants*, not for the mutable lazy-init global state a real codec/parser needs.

## Symptom / repro

A large first-party app (thoth) vendors multiple dist bundles as source into one unit
(bote-core, libro, t-ron, avatara, vyakarana, darshana, sit's read profile, sankoch). Adding
the full **sankoch** bundle (**175 top-level `var` globals** — mostly *mutable lazy-init* state:
crc/huffman/deflate table pointers, scratch buffers, not compile-time constants) tipped the unit
over 1024:

```
error:src/agent.cyr:495: too many initialized globals (max 1024)
```

Minimal shape of the counter (1200 enum members = fine; N `var`s tip it once the unit's total
crosses 1024):

```
enum Big { E_0 = 0; … E_1199 = 1199; }   fn main() { return E_1199; }   # compiles — enums are free
var g0 = 0; var g1 = 1; …                 # each of these consumes one of the 1024 slots
```

## Impact (why raising it matters)

The cap is forcing the **ecosystem to carve lean single-purpose distlib profiles** purely to fit
a *consumer's* global budget, not for any functional reason:

- **sankoch 2.4.9** added a `[lib.zlib]` profile (`dist/sankoch-zlib.cyr`, **53 globals** vs the
  full bundle's 175) so thoth could consume zlib inflate without the LZ4/gzip/xz/bzip2 globals.
- **sit 1.3.0** added a `[lib.read]` read-only profile for the same class of reason.

These profiles are otherwise-unnecessary maintenance surface (a second bundle to regenerate and
keep in sync per release) that exists only to dodge this ceiling. The mutable globals are real
program state that *can't* be enum'd away.

## Ask

1. **Raise the cap** — e.g. to 4096 (matching the variable-per-unit limit), or higher. The
   `gvar_toks` table is a compile-time array; bumping it is cheap relative to the downstream cost.
2. Or **make it configurable** (a `-D`/env knob like the DCE/warn toggles) so a large app can opt
   into a bigger table.
3. Either way, **document the exact counting rule** (top-level `var … = …` count toward it; enum
   members and uninitialized/`extern`-style decls do not) and **reconcile the stale "256"** figure
   in the first-party CLAUDE.md "Max limits per compilation unit" line with the live 1024.

## Next

- Locate the `gvar_toks` (or equivalent) fixed-size table + its `> 1024` check in the codegen
  front-end; confirm whether the 1024 is an array bound or an ABI/offset-encoding constraint
  (if the latter, note what the safe raised ceiling is).
- Add a fixture that defines 1025 initialized globals and asserts it compiles once raised.
