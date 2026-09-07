# Bare local-array slot-write lint (`var a[N]` + `&a + i*8`) — follow-on

> **CONSOLIDATED — v6.4.15 hygiene pass.** Folded into the "DX / cyrlint tooling
> (watching)" list in [roadmap-future.md](../../roadmap-future.md) (batched with the
> syscall-write byte-length gate as one cyrlint slot). Archived; no consumer blocked.

> **Filed 2026-06-25, not yet scheduled.** Carried from the v6.2.44 reactive
> slot; pulled out of the cut because a precise rule needs byte-size-vs-max-index
> analysis the line-based linter can't easily do, and a heuristic version fires
> on existing *intentional* code. The live footgun was already closed by the
> v6.2.1 `var a: i64[N]` typed-array spelling — this lint only catches *new*
> bare-array regressions. Land when the analysis can be done without noise.

**Filed:** 2026-06-25 · **Status:** open / unscheduled · **Severity:** P3 (DX/safety)
**Related:** [`2026-06-11-addr-taken-local-array-static-underreserve.md`](2026-06-11-addr-taken-local-array-static-underreserve.md),
project memory `var_array_byte_sized`.

## What

A lint for the daimon-404-class footgun: a **local** `var a[N]` is N **bytes**
(rounds to 8B; past offset 7 clobbers the next local), but `store64(&a + i*8, …)`
treats it as N **slots** — so the idiom silently under-reserves and writes past
the array. (`var a: i64[N]`, v6.2.1, is the unambiguous slot spelling and fixes
it.) Global `var a[N]` is N slots, so the lint must be **local-scope only**.

## Why it's medium, not small (false-positive exposure)

A naive "warn on `&name + …*8`" fires on **21 existing intentional sites** in
cyrius's own compiler — e.g. `src/frontend/parse.cyr`'s `ends` / `seen_vcnt`
patterns (`store64(&ends + ec*8, …)`), `lib/grp.cyr`'s `field_starts`. Those are
correctly-sized byte-arrays used as slots in hot paths. A useful lint must
distinguish *correctly-sized* (`var a[N*8]` used for N slots) from *under-sized*
(`var a[N]` used for N slots) — i.e. compare the declared byte size to the
maximum `*8` index — which the current line-based cyrlint can't do without
per-array size tracking + index-range inference.

## Suggested approach

Add to `cyrlint` (it already has depth tracking for local/global scope, id
scanning, and `var IDENT[…]` recognition). Track, per fn, each local `var
IDENT[N]` and its byte size; on a `&IDENT + EXPR*8` write, warn only when the
provable max byte offset (`(maxidx)*8 + 8`) exceeds `N`. Where the index range
isn't statically known, prefer silence over noise (or gate behind a strict flag).
Honor `#skip-lint`. Verify zero new warnings on `src/`+`lib/` before wiring into
the gate.
