# Compile-time evaluation (const-eval / `const fn` / comptime) — bake computation, not just data

**Filed:** 2026-07-05 (by a shabdakosh consumer during its v3.0.0 Rust→CYRIUS port —
surfaced porting `dictionary/static_dict.rs`, which is `phf`-feature-gated)
**Status:** PROPOSED — a **capability-gap tracker**, not an urgent fix. Large feature,
narrow immediate payoff. Its scope is decided (the rung was chosen 2026-07-07 — see below); it
needs no further direction before work starts.
**Priority:** low / not a release-blocker. The generated-`.cyr` idiom already covers the
*bulk* of compile-time-data needs; this is about the residual *computation* gap.
**Placement:** **v6.7.x, item C1** of [`roadmap_6.md`](../roadmap_6.md) § v6.7.x — moved there with the rest of the language list on 2026-10-01 (user), after `const` (B1) and the if-expression (B3). *(Re-stamped at the 6.6.20 closeout; this line read "v6.6.x item 2 — UNCHANGED" from the v6.5.21 re-triage until then.)*

> **⟳ Re-stamped 2026-08-14 at v6.5.21 (backlog re-triage).** ⛔ **CORRECTS A MIS-CLASSIFICATION.** A first pass labelled this BLOCKED-ON-MAINTAINER for 'which rung'; an adversarial re-check REFUTED it: **the rung was chosen 2026-07-07**, recorded at `roadmap_6.md:144-149` — **option 1 `const fn`** primary, **option 3 `#phf`** fallback, option 4 declined. **No maintainer decision is outstanding.** Premise otherwise holds (0 hits at 6.5.21). ~~⚠ Rungs 1–2 reuse the `ir_const_fold` fixpoint (`src/common/ir.cyr:747`) which Slot 3 rewrites — build const-eval AFTER Slot 3 or pay the churn twice.~~ *(Struck 2026-10-04 — see the correction block below.)*

> ### ⛔ Correction 2026-10-04 (6.6.16) — the const-eval base is `_CF_TRY`, and a computed initializer is NOT folded
>
> Verified against the 6.6.16 tree; the struck text below (this block's line 11 note, items 1–2 of
> the 2026-08-11 corrections, the `ir_const_fold` clause and "(plus that folding)" in the
> "Current state" bullet, and option 1's "fold fixpoint" and last sentence) is kept for
> history, not deleted.
>
> - **`ir_const_fold` is not the base.** It is an x86-ELF codebuf peephole (`src/common/ir.cyr:672`,
>   a state machine that patches emitted bytes and NOP-fills), called only from `src/main.cyr:2064`
>   inside `if (IR_ENABLED(S) == 1)` / `if (_ir_mode == 51)` — i.e. under opt-in `CYRIUS_IR=3` —
>   and absent from the other six compiler forks (`grep -c ir_const_fold` → 0 in each). There is
>   no "const-fold → DCE → dead-store fixpoint" on the default path for `const fn` to reuse, and no
>   ordering constraint against it. The base for `const fn` is the **parse-time folder `_CF_TRY`**
>   (`src/frontend/parse_decl.cyr:2239`), as `roadmap_6.md` § v6.7.x C1 has said since 2026-10-02.
> - **A module-scope computed initializer is a deferred runtime store, not a fold.** `var A = 6;
>   var B = A * 7; syscall(60, B, 0, 0);` does exit 42, but the x86 image carries a runtime
>   `push rax; mov eax,7; pop rcx; imul rcx; mov [0x600008],rax` sequence: `B` is computed when the
>   program runs. Only an all-literal initializer folds — `var B = 6 * 7;` emits no `imul`
>   (`_CF_TRY`). So the "data that already folds" in the 2026-08-11 item 2 is literal data only, and
>   the residual for this arc includes computed constants, which is exactly what `const fn` buys.

> ### Currency corrections (re-triage 2026-08-11, v6.5.19) — neither changes the verdict
>
> 1. ~~**Stale line reference.** This file cites `ir_const_fold` at `src/main.cyr:1986`. It lives
>    at **`src/common/ir.cyr:735`**.~~ *(Struck 2026-10-04: it is not the base at all — see the
>    correction above.)*
> 2. ~~**"Current state" understates what already ships.** This file says global initializers are
>    "literals (plus that folding)". Since v6.4.74's `_CF_TRY`, a module-scope **computed**
>    initializer really is folded — probe at 6.5.19: `var A = 6; var B = A * 7;` at module
>    scope, `syscall(60, B, 0, 0)` → **exits 42**. Scope the v6.6.x arc to the actual residual,
>    which is *computation* (`const fn` / `#phf`), not data that already folds.~~ *(Struck
>    2026-10-04: exiting 42 shows the value, not a fold — `B` is a deferred runtime store; see the
>    correction above.)*
>
> Premise otherwise holds: `grep -rniE 'comptime|const fn' src cbt` → 0; `grep -rn phf` → 0;
> `const fn two() { return 2; }` → `error:<source>:1:7: expected '=', got fn`.
**Template:** sibling to `2026-06-25-source-level-version-constant.md` (another "value known
at build time isn't reachable from source" gap) — but broader: this is about *evaluating*
at build time, not just *injecting a file*.

## Trigger (the concrete case)

shabdakosh's `dictionary/static_dict.rs` is `#[cfg(feature = "phf")]`: the English dictionary
is a **compile-time `phf::Map`** — a perfect hash baked into the binary by `build.rs`, giving
**zero runtime construction** and collision-free O(1) lookups ("ideal for embedded systems,
WASM, latency-sensitive apps," per its own docs).

CYRIUS has no const-eval, so the port replaced it with a **lazily-built cached singleton** over
the runtime-loaded dictionary (`shabda_dict_english()`): correct and API-faithful, but it trades
phf's compile-time-baked table for a **one-time runtime load**. Measured cost of that load
(shabdakosh `benches/hotpath.bcyr`, x86_64): **~9.5 ms to construct the ~10.6k-entry dict**,
after which lookups are ~134 ns. phf would make the construction ~0 and the lookups collision-free.
So the port is a faithful *surface* match with a real *property* gap: **the one thing that can't
be reproduced is compile-time-computed lookup structure.**

## The gap (precise — it's narrow)

CYRIUS's answer to "compile-time data" is the **generated-`.cyr` idiom** (the `build.rs` port
pattern): an external generator program emits `.cyr` source with the data baked as globals —
shabdakosh's `gen_cmudict.cyr`, varna's inventories, `gen_unicode_data.cyr`, etc. This is
idiomatic, shipped, and covers the *data* case well.

What it does **not** cover is **compile-time computation**:

1. **Baked-in computed structure (phf).** The generator can emit the dictionary *entries*, but
   not an optimal *perfect-hash function* over them. The runtime still loads those entries into a
   general `lib/hashmap` (an O(n) load + ongoing probed lookups) instead of dispatching through a
   collision-free compile-time table. There is no way to compute-and-bake the hash at build time.
2. **Inline computation instead of an external generator.** Every "compute a table at build time"
   task needs a *separate program* (`programs/gen_*.cyr`), built + run + wired into the flow by
   hand, its output checked in and re-synced with every includer + `[lib].modules`. A `const fn` /
   `comptime` block would let that computation live in the source and run during compilation.

## Current state (verified 2026-07-05)

- CYRIUS **already has** ~~**IR-level const-folding** — `ir_const_fold` (`src/main.cyr:1986`, run in the
  "const-fold → DCE → dead-store" fixpoint), plus~~ *(Struck 2026-10-04: that pass is an opt-in
  x86-ELF peephole, not a default-path fixpoint; the default-path folder is the parse-time
  `_CF_TRY` — see the correction at the top.)* "const-fold enum" handling (`src/main.cyr:172`,
  `src/main_win.cyr:109` at 6.6.16 — first cited at `:148` / `:96`; only the line numbers moved).
  This is an **optimization pass** over arithmetic / enum-value literals,
  **not** a user-facing const-eval: global initializers are literals ~~(plus that folding)~~
  *(2026-10-04: plus `_CF_TRY`'s parse-time fold of all-literal arithmetic; a computed initializer
  is a deferred runtime store — see the correction at the top)*, and
  there is **no `const fn`, no comptime block, no compile-time loop/table generation.**
- (At filing) no `const-eval` / `comptime` / `const fn` appeared in `docs/development/roadmap_6.md`.
  **Superseded 2026-07-07**: const-eval/comptime is now SCHEDULED for v6.6.x (language-ergonomics
  minor, early-riser candidate — see roadmap_6.md). The related `source-level-version-constant`
  build-time-value proposal is scheduled separately as a minimal-cut fold in 6.4.x.

## Design space (sketch — maintainer picks the scope)

Const-eval is a large feature and CYRIUS is deliberately minimal (everything i64, single-pass, no
generics). Options, smallest → largest:

1. **`const fn` propagation (minimal).** Mark pure functions `const`; ~~the existing fold fixpoint
   evaluates them~~ *(Struck 2026-10-04: there is no default-path fold fixpoint; the evaluator to
   extend is the parse-time folder `_CF_TRY` — see the correction at the top)* the compiler
   evaluates them over literal args at compile time. Unlocks *computed constants* without a
   generator program. Smallest surface; ~~reuses `ir_const_fold` machinery.~~ *(Struck 2026-10-04:
   it builds on the parse-time folder `_CF_TRY` — see the correction at the top.)*
2. **`comptime { … }` build-time blocks (medium).** A block the compiler executes at build,
   emitting its results as baked globals — subsumes much of the generated-`.cyr` idiom *inline*
   (no separate generator program, no manual include wiring). Bigger: needs a compile-time
   execution model + a way to emit data back into the IR.
3. **A targeted perfect-hash builtin (orthogonal, narrow).** Rather than general const-eval, a
   `#phf`-style intrinsic that takes a checked-in key set and bakes a collision-free lookup — hits
   the static_dict/phf case directly without a general const-eval VM. Much smaller than (2), solves
   the headline trigger, but is single-purpose.
4. **General const-eval VM (full, Rust-miri-scale).** Maximal power, maximal cost; almost certainly
   out of scope for a minimal single-pass compiler.

## Alternatives / why this is "track it," not "do it now"

The generated-`.cyr` idiom is a genuinely good baseline and already ships across the fleet, so the
*bulk* of compile-time-data need is met. const-eval's concrete wins are narrow: (a) eliminate the
one-time load for large static tables (the phf case — ~9.5 ms here, more for bigger tables), and
(b) retire the external-generator ceremony. Both are real ergonomics/perf gains; neither blocks any
release. A crate that needs zero-load lookups today can ship the lazy-singleton port (as shabdakosh
did) with a documented property gap.

## Open questions

- Given the generated-`.cyr` idiom already covers compile-time *data*, is general const-eval worth
  it — or is the **narrow perfect-hash builtin (option 3)** the right ROI, solving the actual
  trigger without a const-eval VM?
- Does any const-eval model fit the **single-pass** compiler design, or does it force a second pass?
- Is `const fn` (option 1) a useful small step on its own (computed constants), independent of the
  bigger comptime/phf questions?

**Bottom line:** the residual gap after the generated-`.cyr` idiom is *baking computation* — most
sharply, phf-style perfect hashing (static_dict's original zero-load lookup). This proposal tracks
that gap and lays out a smallest-to-largest scope ladder; the likely-best ROI is either `const fn`
propagation (small, general) or a targeted perfect-hash builtin (small, solves the trigger), not a
full const-eval VM.
