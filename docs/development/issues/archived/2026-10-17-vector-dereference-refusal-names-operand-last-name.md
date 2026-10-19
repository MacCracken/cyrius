# A `*V` dereference refused into another pointer kind is named by its operand's LAST name, not as written — `ri(*gp(pb))` prints '*pb', `ri(*&b)` '*b', `ri(*h.pv)` '*pv', `ri(**ppb)` '*ppb' — RESOLVED

> ✅ **RESOLVED in v6.7.15** (VC-12, `3033ec7ab` — no decision needed: diagnostics only. `_src_span_nm` (src/frontend/parse_fn.cyr) writes the argument's tokens as the source spells them, at GNPOS + 1024, clear of `_fn_src_name`'s scratch. `_sarg_vdo` and `_dro_check` / `_dro_vcheck` name the argument through it. On x86_64, IR=3, aarch64, cx and PE, the filed repro's five lines quote '*gp(pb)', '*&b', '*h.pv', '*gp(pb)', '*&b'; they quoted '*pb', '*b', '*pv', '*pb', '*b'. `ri(**ppb)` quotes '**ppb', and `rp(*gq(pq))` '*gq(pq)'. Rows: `simd_pointer_param.sh` OKN1 (the filed repro verbatim, its five lines in order) – OKN8, on the five legs; the dereference rows of five gates moved to the source spelling. Mutations: the tree before RED; `_src_span_nm` at GNPOS RED 5. Not closed here (filed, 6.7.16; outside the filed surface): the struct VALUE dereference arms still name the last name, e.g. `take8(*gu(pu))` 'pu' (2026-10-18-struct-value-dereference-refusals-name-operand-last-name.md). CHANGELOG [6.7.15])

**Status:** ✅ **RESOLVED in v6.7.15** (see the banner). Was: 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (its review-fix tree); diagnostics only, the
frontend's text, so every target. Pre-existing for the address-passed arm (`rp(..)` into `*Pt`: 6.7.12's D27
`_dro_check` naming, the lane base c3af6501 prints the same); the lane's a3829d63d (`ri(..)` into `*i64`, 6.7.13's D31
A) matches it deliberately.
**Placement:** 6.7.15 — repair 5 (vectors lane, wave 2, unit V4; placed at the 6.7.15 open, 2026-10-18) — never 7.x.
**Severity:** Low — the refusal is right and lands at the right column; the quoted argument is not the source's.
**Discovered:** 2026-10-17, the review of the 6.7.14 vectors lane (probes i12, c12).

## Reproduction

```cyrius
include "lib/syscalls.cyr"
include "lib/simd.cyr"
struct Hv { k; pv: *f64v2; }
struct Pt { x; y; }
fn ri(p: *i64): i64 { return *p; }
fn rp(p: *Pt): i64 { return p.x; }
fn gp(p: *f64v2): *f64v2 { return p; }
fn main(): i64 {
    var b: f64v2 = f64v2_make(42, 7);
    var pb: *f64v2 = &b;
    var h: Hv; h.pv = pb;
    return ri(*gp(pb)) + ri(*&b) + ri(*h.pv) + rp(*gp(pb)) + rp(*&b);
}
syscall(60, main());
```

```
error:<source>:12:15: cannot pass '*pb' to a parameter that is not a pointer to its vector type in a call to 'ri'
error:<source>:12:29: cannot pass '*b' to a parameter that is not a pointer to its vector type in a call to 'ri'
error:<source>:12:39: cannot pass '*pv' to a parameter that is not a pointer to its vector type in a call to 'ri'
error:<source>:12:51: cannot pass '*pb' to a parameter that is not a pointer to its vector type in a call to 'rp'
error:<source>:12:65: cannot pass '*b' to a parameter that is not a pointer to its vector type in a call to 'rp'
```

The lane base c3af6501 prints the two `rp` lines the same (`'*pb'`, `'*b'`). `ri(**ppb)` prints `'*ppb'` (one `*` short
of the source) and `ri(*GPV)` `'*GPV'` (as written, because the operand is one name).

## Root cause

The refusal (`_dro_check`, src/frontend/parse_fn.cyr, for the address-passed arm; the lane's `_sarg_vdo` (parse_fn.cyr)
with `_dro_vnote` (parse_expr.cyr) for the other pointer kinds) prints `*` plus the last identifier the operand's parse
noted, not the argument's source span.

## Fix direction

Name the argument as the source spells it (`'*gp(pb)'`, `'*&b'`, `'*h.pv'`) — the span from the argument's `*` to its
end, as the method-result argument is named since this release's `_fn_src_name` fix — in both arms.
