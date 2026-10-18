# A `*V` dereference refused into another pointer kind is named by its operand's LAST name, not as written — `ri(*gp(pb))` prints '*pb', `ri(*&b)` '*b', `ri(*h.pv)` '*pv', `ri(**ppb)` '*ppb' — OPEN

**Status:** 🟡 **OPEN** — measured 2026-10-17 on the 6.7.14 vectors lane (its review-fix tree); diagnostics only, the
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
