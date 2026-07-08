# Signed sub-i64 GLOBAL scalar load missing sign-extension

**Filed:** 2026-07-07 (surfaced by a CHANGELOG-prose deferral sweep — the deferral was
claimed "in the inventory" but no issue actually backed it).
**Severity:** P2 — silent miscompile (wrong value, no error/crash) on default builds.
**Component:** `src/frontend/parse_expr.cyr` (global-scalar load), `src/backend/x86/emit.cyr` +
`src/backend/aarch64/emit.cyr` (`EVLOAD_W`).

## Problem

A typed **signed** sub-i64 **global** scalar (`var G: i8/i16/i32`) loads **zero-extended**,
so a negative value reads back as a large positive: `var G: i32 = -1;` → `G` reads
`4294967295`, and every signed compare/arith on it is wrong.

Confirmed at `src/frontend/parse_expr.cyr:563-566`:
```
var gvsz = L64(_vars_base + idx * 8);   # raw POSITIVE var_size (1/2/4)
if (gvsz < 8) {
    SEXW(S, gvsz);
    EVLOAD_W(S, idx, gvsz);             # positive width → zero-extend
```
`gvsz` is never negated for a signed global, so `EVLOAD_W` takes the zero-extend arm.
The aarch64 comment at `emit.cyr:1959` corroborates: *"EVLOAD_W has none — its only caller
passes a positive var_size."*

## Why it was orphaned

The v6.3.35 default-path miscompile inventory wired sign-extension for **locals**
(negative-width sentinel), **struct fields**, and **call-args** — and deferred the
**global** scalar case with the bullet *"Deferred as narrow follow-ons: signed sub-i64
globals sign-extension (rare)."* That deferral lived only in CHANGELOG prose: the inventory
issue's items [1]/[2]/[8] are local/field/call-arg; the separately-filed K2 issue covers
only the typed-global **SIGSEGV crash**, not sign-extension. So this fell through.

## Fix

Mirror the v6.3.35 local negative-width sentinel: pass a **negative** `gvsz` for a signed
global so `EVLOAD_W` routes through the `movsx`/`movsxd` arms (x86 — `_EMIT_NLOAD_RCX`
already handles −1/−2/−4) and the signed `ldursb`/`ldursh`/`ldursw` arms (aarch64 — which
`EVLOAD_W` currently **lacks** and must gain).

> **SCOPE FINDING (2026-07-08, assessed for v6.4.21, DEFERRED — bigger than filed).** The
> hard part is WHERE to store the global's signedness — globals record none today
> (parse_decl.cyr:768 distinguishes `i32`/`u32` but keeps only the width). It can't reuse:
> - **var_size** (`_vars_base`) — `fixup.cyr` (x86/aarch64/pe) SUMS it (`totvar`/`cumul`)
>   to lay out the global data section, so any sign/flag encoding corrupts the layout.
> - **the type table** (`_vart_base`/`GVTYPE`) — 6 readers consume it directly
>   (parse_expr:558, parse.cyr:1242, parse_decl:328/466 struct-field, parse_fn:956/1299
>   type-check); `vt<0` already means pointer-scale. Overloading ripples.
>
> So the clean fix is a **new 8th var-family table** `_vsgn_base` (parallel to the 7 in
> `util.cyr`): a fixed init offset in ALL 7 `main_*.cyr` forks + a new link in the
> **cybs-fragile grow-chain** (`_grow_g8`; the chain is one-table-per-fn ON PURPOSE — see
> the util.cyr warning — so this is a seed→cybs→cycc risk) + set it at global-scalar decl
> (capture `ann_signed`) + read it in the load path + add aarch64 `EVLOAD_W` signed arms.
> That is **~the size of the v6.4.21 LEXID relocation** (a two-step layout change), so it
> was deferred to its OWN focused release rather than stacked on the LEXID bump. The only
> smaller path — overloading an unused slot (`_venid`/`_vecv`, 0 for sub-i64 scalars) — is a
> semantic hack in the seed-trusted frontend and was rejected. Do this as a standalone slot.

## Acceptance

`var G: i32 = -1; if (G < 0) {...}` takes the branch; a sub-i64 signed-global regression
test passes on x86 + aarch64; cycc self-hosts byte-identical (src/ has no signed sub-i64
globals, so the change is a real behavior fix showing differential codegen-diff>0 only on
the new test, status-diff=0). Two-step bootstrap if it perturbs cycc's own layout.
